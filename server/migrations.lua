local DB = NEXM_INTERNAL.Modules.InternalDB or NEXM_INTERNAL.Modules.DB
local Errors = NEXM_INTERNAL.Modules.Errors
local Validation = NEXM_INTERNAL.Modules.Validation
local Logger = NEXM_INTERNAL.Modules.Logger
local Ownership = NEXM_INTERNAL.Modules.Ownership
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local Migrations = {}
local registry = {}

local function stableSerialize(value, seen)
    local valueType = type(value)
    if valueType == 'nil' then return 'nil' end
    if valueType == 'boolean' or valueType == 'number' then return tostring(value) end
    if valueType == 'string' then return ('%q'):format(value) end
    if valueType ~= 'table' then return '<' .. valueType .. '>' end

    seen = seen or {}
    if seen[value] then return '<cycle>' end
    seen[value] = true

    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    local parts = { '{' }
    for _, key in ipairs(keys) do
        parts[#parts + 1] = stableSerialize(key, seen)
        parts[#parts + 1] = '='
        parts[#parts + 1] = stableSerialize(value[key], seen)
        parts[#parts + 1] = ';'
    end
    parts[#parts + 1] = '}'

    seen[value] = nil
    return table.concat(parts)
end

local function adler32(text)
    local a, b = 1, 0
    for index = 1, #text do
        a = (a + text:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return ('%08x'):format(b * 65536 + a)
end

local function migrationChecksum(migration)
    return 'adler32:' .. adler32(stableSerialize({
        id = migration.id,
        statements = migration.statements,
        transactional = migration.transactional ~= false
    }))
end

local function normalizeStatements(statements)
    local ok, err = Validation.Table(statements, {
        name = 'migration statements',
        minEntries = 1,
        maxEntries = 128
    })
    if not ok then return nil, err end

    local normalized = {}
    for index, statement in ipairs(statements) do
        if type(statement) == 'string' then
            local valid, stringErr = Validation.String(statement, {
                name = ('migration statement %d'):format(index),
                nonEmpty = true,
                min = 1,
                max = 65535
            })
            if not valid then return nil, stringErr end
            normalized[#normalized + 1] = { query = statement, values = {} }
        elseif type(statement) == 'table' and type(statement.query) == 'string' then
            normalized[#normalized + 1] = {
                query = statement.query,
                values = type(statement.values) == 'table' and statement.values or {}
            }
        else
            return nil, Errors.Create(
                Codes.INVALID_ARGUMENT,
                'Migration statement must be a SQL string or query descriptor',
                { index = index }
            )
        end
    end

    return normalized, nil
end

function Migrations.Bootstrap()
    local _, err = DB.Query([[
        CREATE TABLE IF NOT EXISTS `nexm_migrations` (
            `resource` VARCHAR(128) NOT NULL,
            `migration` VARCHAR(128) NOT NULL,
            `checksum` VARCHAR(64) NOT NULL,
            `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`resource`, `migration`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]], {}, 'nexm_core')

    if err then
        return false, Errors.Wrap(Codes.MIGRATION_ERROR, 'Failed to create migration tracking table', err)
    end

    return true, nil
end

function Migrations.Register(resourceName, definition, ownerResource)
    local owner = ownerResource or Ownership.Resolve()
    local resource = resourceName or owner

    local validResource, resourceErr = Validation.String(resource, {
        name = 'migration resource',
        nonEmpty = true,
        min = 1,
        max = 128,
        pattern = '^[%w%._%-]+$'
    })
    if not validResource then return false, resourceErr end

    if owner ~= 'nexm_core' and resource ~= owner then
        return false, Errors.Create(
            Codes.OWNER_MISMATCH,
            'A resource cannot register migrations for another resource',
            { ownerResource = owner, requestedResource = resource }
        )
    end

    if type(definition) ~= 'table' then
        return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Migration definition must be a table')
    end

    local validId, idErr = Ownership.ValidateLocalName(definition.id)
    if not validId then return false, idErr end

    local statements, statementsErr = normalizeStatements(definition.statements)
    if not statements then return false, statementsErr end

    registry[resource] = registry[resource] or {}
    if registry[resource][definition.id] then
        return false, Errors.Create(
            Codes.REGISTRATION_EXISTS,
            'Migration is already registered',
            { resource = resource, migration = definition.id }
        )
    end

    local migration = {
        id = definition.id,
        statements = statements,
        transactional = definition.transactional ~= false,
        ownerResource = owner,
        registeredAt = os.time()
    }
    migration.checksum = migrationChecksum(migration)
    registry[resource][definition.id] = migration

    return true, nil
end

local function getApplied(resource)
    local rows, err = DB.Query(
        'SELECT `migration`, `checksum` FROM `nexm_migrations` WHERE `resource` = ?',
        { resource },
        resource
    )
    if err then return nil, err end

    local applied = {}
    for _, row in ipairs(rows or {}) do
        applied[row.migration] = row.checksum
    end
    return applied, nil
end

local function applyMigration(resource, migration)
    local tracking = {
        query = 'INSERT INTO `nexm_migrations` (`resource`, `migration`, `checksum`) VALUES (?, ?, ?)',
        values = { resource, migration.id, migration.checksum }
    }

    if migration.transactional then
        local queries = {}
        for _, statement in ipairs(migration.statements) do
            queries[#queries + 1] = { query = statement.query, values = statement.values }
        end
        queries[#queries + 1] = tracking

        local ok, err = DB.Transaction(queries, nil, resource)
        if not ok then return false, err end
    else
        Logger.Warn(
            'Running non-transactional migration; DDL rollback semantics depend on the database engine',
            { resource = resource, migration = migration.id },
            migration.ownerResource
        )

        for _, statement in ipairs(migration.statements) do
            local _, err = DB.Query(statement.query, statement.values, resource)
            if err then return false, err end
        end

        local _, err = DB.Insert(tracking.query, tracking.values, resource)
        if err then return false, err end
    end

    Logger.Info('Migration applied', { resource = resource, migration = migration.id }, migration.ownerResource)
    return true, nil
end

function Migrations.Run(resource)
    local migrations = registry[resource] or {}
    local applied, appliedErr = getApplied(resource)
    if not applied then
        return false, Errors.Wrap(Codes.MIGRATION_ERROR, 'Failed to read applied migrations', appliedErr, { resource = resource })
    end

    local ids = {}
    for id in pairs(migrations) do ids[#ids + 1] = id end
    table.sort(ids)

    for _, id in ipairs(ids) do
        local migration = migrations[id]
        local existingChecksum = applied[id]

        if existingChecksum and existingChecksum ~= migration.checksum then
            local err = Errors.Create(
                Codes.MIGRATION_CHECKSUM_MISMATCH,
                'Applied migration checksum does not match registered migration',
                {
                    resource = resource,
                    migration = id,
                    appliedChecksum = existingChecksum,
                    registeredChecksum = migration.checksum
                }
            )
            Logger.Infrastructure(err, 'migrations', migration.ownerResource)
            return false, err
        end

        if not existingChecksum then
            local ok, err = applyMigration(resource, migration)
            if not ok then
                return false, Errors.Wrap(
                    Codes.MIGRATION_ERROR,
                    'Migration failed',
                    err,
                    { resource = resource, migration = id }
                )
            end
        end
    end

    return true, nil
end

function Migrations.RunCore()
    return Migrations.Run('nexm_core')
end

function Migrations.CleanupOwner(ownerResource)
    if ownerResource == 'nexm_core' then return end
    registry[ownerResource] = nil
end

function Migrations.GetRegistered(resource)
    local out = {}
    for id, migration in pairs(registry[resource] or {}) do
        out[id] = {
            id = id,
            checksum = migration.checksum,
            transactional = migration.transactional,
            ownerResource = migration.ownerResource,
            registeredAt = migration.registeredAt
        }
    end
    return out
end

NEXM_INTERNAL.Modules.Migrations = Migrations
