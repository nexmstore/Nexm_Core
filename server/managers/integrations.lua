local RegistryBase = NEXM_INTERNAL.Modules.RegistryBase
local Ownership = NEXM_INTERNAL.Modules.Ownership
local Errors = NEXM_INTERNAL.Modules.Errors
local Validation = NEXM_INTERNAL.Modules.Validation
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local SemVer = NEXM_INTERNAL.Modules.SemVer
local Logger = NEXM_INTERNAL.Modules.Logger
local State = NEXM_INTERNAL.Modules.State

local Integrations = {}
local registry = RegistryBase.New('integration')
local copy = RegistryBase.Copy
local selections = {}

local function composite(category, name)
    return category .. '.' .. name
end

local function ambiguousCode(category)
    if category == 'inventory' then
        return Codes.AMBIGUOUS_INVENTORY_INTEGRATION
    end
    return Codes.AMBIGUOUS_INTEGRATION
end

function Integrations.RegisterInternal(definition, ownerResource)
    if type(definition) ~= 'table' then
        return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Integration definition must be a table')
    end

    local owner = ownerResource or Ownership.Resolve()
    local validCategory, categoryErr = Ownership.ValidateLocalName(definition.category)
    if not validCategory then return false, categoryErr end
    local validName, nameErr = Ownership.ValidateLocalName(definition.name)
    if not validName then return false, nameErr end

    local version = definition.version or '0.0.0'
    local parsedVersion, versionErr = SemVer.Parse(version)
    if not parsedVersion then return false, versionErr end

    local validState, stateErr = Validation.String(definition.state or 'REGISTERED', {
        name = 'integration state', nonEmpty = true, min = 1, max = 64, pattern = '^[%w%._%-]+$'
    })
    if not validState then return false, stateErr end

    local key = composite(definition.category, definition.name)
    local metadata = {
        category = definition.category,
        name = definition.name,
        version = version,
        capabilities = type(definition.capabilities) == 'table' and definition.capabilities or {},
        critical = definition.critical == true,
        state = definition.state or 'REGISTERED'
    }

    local ok, recordOrErr = registry:Register(key, definition.adapter, metadata, owner)
    if not ok then return false, recordOrErr end
    return true, nil
end

local function candidatesFor(category)
    local candidates = {}
    for _, item in ipairs(registry:ListMetadata()) do
        local metadata = item.metadata
        if metadata.category == category and (metadata.state == 'AVAILABLE' or metadata.state == 'HEALTHY') then
            candidates[#candidates + 1] = metadata.name
        end
    end
    table.sort(candidates)
    return candidates
end


local function selectionError(category, code, message, context)
    local err = Errors.Create(code, message, context)
    Logger.Infrastructure(err, 'integration:' .. category, 'nexm_core')
    return false, err
end

local function contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then return true end
    end
    return false
end

function Integrations.Select(category, configuredName, priority)
    local existing = selections[category]
    if existing then
        if configuredName and configuredName ~= 'auto' and configuredName ~= existing.name then
            local err = Errors.Create(
                Codes.INTEGRATION_SELECTION_LOCKED,
                'Critical integration selection is sticky after initialization',
                { category = category, selected = existing.name, requested = configuredName }
            )
            Logger.Infrastructure(err, 'integration:' .. category, 'nexm_core')
            return false, err
        end

        local record = registry:GetRecord(composite(category, existing.name))
        local available = record and (record.metadata.state == 'AVAILABLE' or record.metadata.state == 'HEALTHY')
        if not available then
            local err = Errors.Create(
                Codes.INTEGRATION_UNAVAILABLE,
                'Selected integration is unavailable; automatic hot-switch is disabled',
                { category = category, selected = existing.name }
            )
            Logger.Infrastructure(err, 'integration:' .. category, 'nexm_core')
            return false, err
        end

        existing.state = 'AVAILABLE'
        return true, existing.name
    end

    local candidates = candidatesFor(category)

    if configuredName and configuredName ~= 'auto' then
        if not contains(candidates, configuredName) then
            return selectionError(
                category,
                Codes.INTEGRATION_UNAVAILABLE,
                'Configured integration is not available',
                { category = category, configured = configuredName, detected = candidates }
            )
        end
        selections[category] = { name = configuredName, selectedAt = os.time() }
        return true, configuredName
    end

    if #candidates == 0 then
        return selectionError(
            category,
            Codes.INTEGRATION_UNAVAILABLE,
            'No supported integration is available',
            { category = category }
        )
    end

    if #candidates == 1 then
        selections[category] = { name = candidates[1], selectedAt = os.time() }
        return true, candidates[1]
    end

    local configuredPriority = type(priority) == 'table' and priority or {}
    if #configuredPriority > 0 then
        for _, name in ipairs(configuredPriority) do
            if contains(candidates, name) then
                selections[category] = { name = name, selectedAt = os.time(), fromPriority = true }
                return true, name
            end
        end
    end

    return selectionError(
        category,
        ambiguousCode(category),
        'Multiple active integrations were detected and no explicit priority resolved the ambiguity',
        { category = category, detected = candidates }
    )
end

function Integrations.GetSelected(category)
    local selected = selections[category]
    return selected and selected.name or nil
end

function Integrations.GetName(category)
    return Integrations.GetSelected(category)
end

function Integrations.IsAvailable(category, name)
    name = name or Integrations.GetSelected(category)
    if not name then return false end
    local record = registry:GetRecord(composite(category, name))
    return record ~= nil and (record.metadata.state == 'AVAILABLE' or record.metadata.state == 'HEALTHY')
end

function Integrations.GetCapabilities(category, name)
    name = name or Integrations.GetSelected(category)
    if not name then return nil end
    local record = registry:GetRecord(composite(category, name))
    return record and copy(record.metadata.capabilities) or nil
end


function Integrations.SetStateInternal(category, name, state, ownerResource)
    local record = registry:GetRecord(composite(category, name))
    if not record then
        return false, Errors.Create(Codes.REGISTRATION_NOT_FOUND, 'Integration registration was not found', { category = category, name = name })
    end
    if ownerResource and record.ownerResource ~= ownerResource then
        return false, Errors.Create(Codes.OWNER_MISMATCH, 'Integration owner mismatch', { category = category, name = name, ownerResource = ownerResource, existingOwnerResource = record.ownerResource })
    end
    record.metadata.state = state
    return true, nil
end

function Integrations.GetAdapterInternal(category, name)
    local record = registry:GetRecord(composite(category, name))
    return record and record.value or nil
end


function Integrations.SetSelectedInternal(category, name, metadata)
    if name == nil then
        selections[category] = nil
        return true, nil
    end
    local record = registry:GetRecord(composite(category, name))
    if not record then
        return false, Errors.Create(Codes.REGISTRATION_NOT_FOUND, 'Integration registration was not found', { category = category, name = name })
    end
    selections[category] = {
        name = name,
        selectedAt = (metadata and metadata.selectedAt) or os.time(),
        state = (metadata and metadata.state) or record.metadata.state,
        fallback = metadata and metadata.fallback == true or false
    }
    return true, nil
end

function Integrations.ClearSelectedInternal(category)
    selections[category] = nil
    return true, nil
end

function Integrations.GetState(category)
    local name = Integrations.GetSelected(category)
    if not name then local c = State and State.GetComponent and State.GetComponent(category) or nil; return c and c.state or nil end
    local record = registry:GetRecord(composite(category, name))
    if not record then return selections[category] and selections[category].state or 'UNAVAILABLE' end
    return record.metadata.state
end

function Integrations.IsHealthy(category)
    local state = Integrations.GetState(category)
    return state == 'HEALTHY' or state == 'AVAILABLE'
end

function Integrations.GetMetadata(category, name)
    name = name or Integrations.GetSelected(category)
    if not name then return nil end
    local record = registry:GetRecord(composite(category, name))
    if not record then return nil end
    return {
        category = category,
        name = name,
        ownerResource = record.ownerResource,
        registeredAt = record.registeredAt,
        version = record.metadata.version,
        capabilities = copy(record.metadata.capabilities),
        critical = record.metadata.critical == true,
        state = record.metadata.state
    }
end

function Integrations.Count() return registry:Count() end
function Integrations.ListMetadata() return registry:ListMetadata() end
function Integrations.CleanupOwner(ownerResource)
    local removed = registry:RemoveOwned(ownerResource)
    for category, selected in pairs(selections) do
        local key = composite(category, selected.name)
        local record = registry:GetRecord(key)
        if not record then
            -- Keep the sticky selection name. Runtime failover is intentionally not performed.
            selections[category].state = 'UNAVAILABLE'
        end
    end
    return removed
end

NEXM_INTERNAL.Managers.Integrations = Integrations
