local Constants = NEXM_INTERNAL.Modules.Constants
local Errors = NEXM_INTERNAL.Modules.Errors
local Validation = NEXM_INTERNAL.Modules.Validation
local Player = NEXM_INTERNAL.Modules.Player
local Logger = NEXM_INTERNAL.Modules.Logger
local Codes = Constants.ERROR_CODES

local TemporaryAppearance = {}

local RESOURCE = GetCurrentResourceName and GetCurrentResourceName() or 'nexm_core'
local DATA_PATH = 'data/temporary_appearances.json'
local BACKUP_PATH = 'data/temporary_appearances.bak.json'
local TEMP_PATH = 'data/temporary_appearances.tmp.json'
local SCHEMA_VERSION = 1
local records = {}

local function config()
    local cfg = Config and Config.TemporaryAppearance or {}
    return {
        maxPayloadBytes = tonumber(cfg.maxPayloadBytes) or 16384,
        maxDrawable = tonumber(cfg.maxDrawable) or 4096,
        maxTexture = tonumber(cfg.maxTexture) or 4096,
        maxPalette = tonumber(cfg.maxPalette) or 3,
        maxOwnerLength = tonumber(cfg.maxOwnerLength) or 128
    }
end

local function createError(code, message, context)
    return Errors.Create(code, message, context)
end

local function validateOwner(owner)
    local cfg = config()
    local ok, err = Validation.String(owner, {
        name = 'temporary appearance owner',
        nonEmpty = true,
        min = 1,
        max = cfg.maxOwnerLength,
        pattern = '^[%w%._%-]+$'
    })
    if not ok then return nil, err end
    return owner, nil
end

local function validateModel(value)
    local ok, err = Validation.Integer(value, {
        name = 'appearance.model',
        min = -2147483648,
        max = 4294967295
    })
    if not ok then return nil, err end
    if value == 0 then
        return nil, createError(Codes.TEMP_APPEARANCE_INVALID, 'Appearance model hash cannot be zero')
    end
    return value, nil
end

local function getIndexedEntry(container, index)
    if type(container) ~= 'table' then return nil end
    return container[tostring(index)] or container[index]
end

local function normalizeAppearance(appearance)
    local cfg = config()
    local ok, err = Validation.Table(appearance, { name = 'appearance', maxEntries = 8 })
    if not ok then return nil, err end

    local version = appearance.version == nil and 1 or appearance.version
    ok, err = Validation.Integer(version, { name = 'appearance.version', min = 1, max = 1 })
    if not ok then return nil, err end

    local model
    model, err = validateModel(appearance.model)
    if not model then return nil, err end

    ok, err = Validation.Table(appearance.components, { name = 'appearance.components', minEntries = 12, maxEntries = 12 })
    if not ok then return nil, err end
    ok, err = Validation.Table(appearance.props, { name = 'appearance.props', minEntries = 8, maxEntries = 8 })
    if not ok then return nil, err end

    local normalized = {
        version = 1,
        model = model,
        components = {},
        props = {}
    }

    for componentId = 0, 11 do
        local item = getIndexedEntry(appearance.components, componentId)
        ok, err = Validation.Table(item, { name = ('appearance.components[%d]'):format(componentId), maxEntries = 3 })
        if not ok then return nil, err end

        local drawable, texture, palette = item.drawable, item.texture, item.palette
        ok, err = Validation.Integer(drawable, {
            name = ('appearance.components[%d].drawable'):format(componentId), min = 0, max = cfg.maxDrawable
        }); if not ok then return nil, err end
        ok, err = Validation.Integer(texture, {
            name = ('appearance.components[%d].texture'):format(componentId), min = 0, max = cfg.maxTexture
        }); if not ok then return nil, err end
        ok, err = Validation.Integer(palette, {
            name = ('appearance.components[%d].palette'):format(componentId), min = 0, max = cfg.maxPalette
        }); if not ok then return nil, err end

        normalized.components[tostring(componentId)] = {
            drawable = drawable,
            texture = texture,
            palette = palette
        }
    end

    for propId = 0, 7 do
        local item = getIndexedEntry(appearance.props, propId)
        ok, err = Validation.Table(item, { name = ('appearance.props[%d]'):format(propId), maxEntries = 2 })
        if not ok then return nil, err end

        local drawable, texture = item.drawable, item.texture
        ok, err = Validation.Integer(drawable, {
            name = ('appearance.props[%d].drawable'):format(propId), min = -1, max = cfg.maxDrawable
        }); if not ok then return nil, err end
        ok, err = Validation.Integer(texture, {
            name = ('appearance.props[%d].texture'):format(propId), min = 0, max = cfg.maxTexture
        }); if not ok then return nil, err end

        if drawable == -1 then texture = 0 end
        normalized.props[tostring(propId)] = { drawable = drawable, texture = texture }
    end

    local encodedOk, encoded = pcall(json.encode, normalized)
    if not encodedOk or type(encoded) ~= 'string' then
        return nil, createError(Codes.TEMP_APPEARANCE_INVALID, 'Appearance snapshot could not be serialized')
    end
    if #encoded > cfg.maxPayloadBytes then
        return nil, createError(Codes.TEMP_APPEARANCE_INVALID, 'Appearance snapshot exceeds configured size limit', {
            bytes = #encoded,
            maxBytes = cfg.maxPayloadBytes
        })
    end

    return normalized, nil
end

local function cloneAppearance(appearance)
    local copy = {
        version = appearance.version,
        model = appearance.model,
        components = {},
        props = {}
    }
    for i = 0, 11 do
        local item = appearance.components[tostring(i)]
        copy.components[tostring(i)] = {
            drawable = item.drawable,
            texture = item.texture,
            palette = item.palette
        }
    end
    for i = 0, 7 do
        local item = appearance.props[tostring(i)]
        copy.props[tostring(i)] = { drawable = item.drawable, texture = item.texture }
    end
    return copy
end

local function cloneRecord(record)
    if type(record) ~= 'table' or type(record.appearance) ~= 'table' then return nil end
    return {
        version = 1,
        owner = record.owner,
        createdAt = record.createdAt,
        appearance = cloneAppearance(record.appearance)
    }
end

local function decodeFile(path)
    local raw = LoadResourceFile and LoadResourceFile(RESOURCE, path) or nil
    if type(raw) ~= 'string' or raw == '' then return nil, 'missing' end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return nil, 'invalid_json' end
    return decoded, nil
end

local function sanitizePersisted(decoded)
    if type(decoded) ~= 'table' then return {}, true end
    local sourceRecords = decoded.records
    if type(sourceRecords) ~= 'table' then
        -- Accept a direct player->owner map if an early development build wrote it.
        sourceRecords = decoded
    end

    local clean, changed = {}, false
    for identifier, owners in pairs(sourceRecords) do
        local idOk = Validation.Identifier(identifier, { name = 'persisted player identifier', max = 256 })
        if idOk and type(owners) == 'table' then
            for owner, record in pairs(owners) do
                local normalizedOwner = validateOwner(owner)
                local appearance = type(record) == 'table' and record.appearance or nil
                local normalizedAppearance = appearance and normalizeAppearance(appearance) or nil
                local createdAt = type(record) == 'table' and tonumber(record.createdAt) or nil
                if normalizedOwner and normalizedAppearance and createdAt and createdAt > 0 then
                    clean[identifier] = clean[identifier] or {}
                    clean[identifier][normalizedOwner] = {
                        version = 1,
                        owner = normalizedOwner,
                        createdAt = math.floor(createdAt),
                        appearance = normalizedAppearance
                    }
                else
                    changed = true
                end
            end
        else
            changed = true
        end
    end
    return clean, changed
end

local function encodeStore()
    local ok, encoded = pcall(json.encode, {
        version = SCHEMA_VERSION,
        records = records
    })
    if not ok or type(encoded) ~= 'string' then
        return nil, createError(Codes.TEMP_APPEARANCE_PERSISTENCE_FAILED, 'Failed to encode temporary appearance persistence data')
    end
    return encoded, nil
end

local function saveFile(path, data)
    if not SaveResourceFile then
        return false, createError(Codes.TEMP_APPEARANCE_PERSISTENCE_FAILED, 'SaveResourceFile is unavailable')
    end
    local ok, result = pcall(SaveResourceFile, RESOURCE, path, data, #data)
    if not ok or result == false then
        return false, createError(Codes.TEMP_APPEARANCE_PERSISTENCE_FAILED, 'Failed to persist temporary appearance data', {
            path = path
        })
    end
    return true, nil
end

local function persist()
    local encoded, encodeErr = encodeStore()
    if not encoded then return false, encodeErr end

    -- Stage and validate a temporary copy before replacing the primary file.
    local ok, err = saveFile(TEMP_PATH, encoded)
    if not ok then return false, err end
    local staged = decodeFile(TEMP_PATH)
    if type(staged) ~= 'table' then
        return false, createError(Codes.TEMP_APPEARANCE_PERSISTENCE_FAILED, 'Temporary appearance staging verification failed')
    end

    ok, err = saveFile(DATA_PATH, encoded)
    if not ok then return false, err end
    -- Backup mirrors the latest fully encoded snapshot and is used when the
    -- primary file is unreadable after an abnormal shutdown.
    local backupOk, backupErr = saveFile(BACKUP_PATH, encoded)
    if not backupOk then
        Logger.Warn('Temporary appearance backup write failed; primary file remains valid', {
            error = backupErr and backupErr.code
        }, 'nexm_core')
    end
    return true, nil
end

local function initialize()
    local decoded, reason = decodeFile(DATA_PATH)
    local usedBackup = false
    if not decoded then
        local backup = decodeFile(BACKUP_PATH)
        if backup then decoded = backup; usedBackup = true end
    end

    if decoded then
        local changed
        records, changed = sanitizePersisted(decoded)
        if usedBackup or changed then
            local ok, err = persist()
            if not ok then
                Logger.Warn('Temporary appearance persistence loaded but could not be repaired', {
                    error = err and err.code,
                    usedBackup = usedBackup
                }, 'nexm_core')
            end
        end
        Logger.Info('Temporary appearance recovery persistence loaded', {
            source = usedBackup and 'backup' or 'primary'
        }, 'nexm_core')
        return
    end

    records = {}
    local ok, err = persist()
    if not ok then
        Logger.Warn('Temporary appearance persistence started in memory-only fail-safe state', {
            reason = reason,
            error = err and err.code
        }, 'nexm_core')
    else
        Logger.Info('Temporary appearance recovery persistence initialized', {}, 'nexm_core')
    end
end

local function resolveIdentifier(source)
    local ok, err = Validation.Source(source, { name = 'source' })
    if not ok then return nil, err end
    -- Player.GetIdentifier is the existing Core canonical character identity,
    -- not a transient server source and not a client-supplied identifier.
    return Player.GetIdentifier(source)
end

function TemporaryAppearance.Validate(appearance)
    return normalizeAppearance(appearance)
end

function TemporaryAppearance.Save(source, owner, appearance, options)
    local identifier, idErr = resolveIdentifier(source)
    if not identifier then return false, idErr end
    local normalizedOwner, ownerErr = validateOwner(owner)
    if not normalizedOwner then return false, ownerErr end

    local bucket = records[identifier]
    if bucket and bucket[normalizedOwner] and not (type(options) == 'table' and options.force == true) then
        return true, {
            existing = true,
            record = cloneRecord(bucket[normalizedOwner])
        }
    end

    local normalizedAppearance, appearanceErr = normalizeAppearance(appearance)
    if not normalizedAppearance then return false, appearanceErr end

    local previousBucket = bucket
    local previousRecord = bucket and bucket[normalizedOwner] or nil
    bucket = bucket or {}
    records[identifier] = bucket
    bucket[normalizedOwner] = {
        version = 1,
        owner = normalizedOwner,
        createdAt = os.time(),
        appearance = normalizedAppearance
    }

    local persisted, persistErr = persist()
    if not persisted then
        if previousRecord then
            bucket[normalizedOwner] = previousRecord
        elseif previousBucket then
            bucket[normalizedOwner] = nil
        else
            records[identifier] = nil
        end
        return false, persistErr
    end

    Logger.Info('Temporary appearance saved', { owner = normalizedOwner }, 'nexm_core')
    return true, {
        existing = false,
        record = cloneRecord(bucket[normalizedOwner])
    }
end

function TemporaryAppearance.Get(source, owner)
    local identifier, idErr = resolveIdentifier(source)
    if not identifier then return nil, idErr end
    local normalizedOwner, ownerErr = validateOwner(owner)
    if not normalizedOwner then return nil, ownerErr end
    local record = records[identifier] and records[identifier][normalizedOwner] or nil
    if not record then
        return nil, createError(Codes.TEMP_APPEARANCE_NOT_FOUND, 'No pending temporary appearance recovery record', {
            owner = normalizedOwner
        })
    end
    Logger.Debug('Temporary appearance restore requested', { owner = normalizedOwner }, 'nexm_core')
    return cloneRecord(record), nil
end

function TemporaryAppearance.Has(source, owner)
    local identifier, idErr = resolveIdentifier(source)
    if not identifier then return false, idErr end
    local normalizedOwner, ownerErr = validateOwner(owner)
    if not normalizedOwner then return false, ownerErr end
    return records[identifier] ~= nil and records[identifier][normalizedOwner] ~= nil, nil
end

function TemporaryAppearance.Clear(source, owner, reason)
    local identifier, idErr = resolveIdentifier(source)
    if not identifier then return false, idErr end
    local normalizedOwner, ownerErr = validateOwner(owner)
    if not normalizedOwner then return false, ownerErr end
    local bucket = records[identifier]
    local existing = bucket and bucket[normalizedOwner] or nil
    if not existing then
        return false, createError(Codes.TEMP_APPEARANCE_NOT_FOUND, 'No pending temporary appearance recovery record', {
            owner = normalizedOwner
        })
    end

    bucket[normalizedOwner] = nil
    if next(bucket) == nil then records[identifier] = nil end
    local persisted, persistErr = persist()
    if not persisted then
        records[identifier] = records[identifier] or bucket
        records[identifier][normalizedOwner] = existing
        return false, persistErr
    end

    Logger.Info('Temporary appearance restore acknowledged and cleared', {
        owner = normalizedOwner,
        reason = type(reason) == 'string' and reason or 'verified_restore'
    }, 'nexm_core')
    return true, nil
end

function TemporaryAppearance.DebugSummary(source)
    if source == 0 then
        local players, total = 0, 0
        for _, owners in pairs(records) do
            players = players + 1
            for _ in pairs(owners) do total = total + 1 end
        end
        return { players = players, records = total }
    end
    local identifier, err = resolveIdentifier(source)
    if not identifier then return nil, err end
    local summary = { records = {} }
    for owner, record in pairs(records[identifier] or {}) do
        summary.records[#summary.records + 1] = { owner = owner, createdAt = record.createdAt }
    end
    table.sort(summary.records, function(a, b) return a.owner < b.owner end)
    return summary, nil
end

initialize()

RegisterCommand('nexmtempappearance', function(source)
    if not (Config and Config.Debug == true) then
        if source == 0 then print('[NEXM Core] /nexmtempappearance is available only when Config.Debug=true') end
        return
    end
    local summary, err = TemporaryAppearance.DebugSummary(source)
    if not summary then
        if source == 0 then
            print(('[NEXM Core] Temporary appearance debug failed: %s'):format(err and err.code or 'unknown'))
        else
            TriggerClientEvent('nexm_core:client:temporaryAppearanceDebug', source, {
                ('Temporary appearance debug failed: %s'):format(err and err.code or 'unknown')
            })
        end
        return
    end
    if source == 0 then
        print(('[NEXM Core] Temporary appearance records: players=%d records=%d'):format(summary.players, summary.records))
        return
    end
    local lines = { ('Pending temporary appearance records: %d'):format(#summary.records) }
    for _, item in ipairs(summary.records) do
        lines[#lines + 1] = ('owner=%s createdAt=%s'):format(item.owner, tostring(item.createdAt))
    end
    TriggerClientEvent('nexm_core:client:temporaryAppearanceDebug', source, lines)
end, false)

NEXM_INTERNAL.Modules.TemporaryAppearance = TemporaryAppearance
