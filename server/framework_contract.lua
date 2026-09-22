local Errors = NEXM_INTERNAL.Modules.Errors
local Validation = NEXM_INTERNAL.Modules.Validation
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local FrameworkContract = {}

-- Canonical framework capability schema (Phase 3 + Phase 4 economy extension). Every adapter must explicitly declare
-- every field below as boolean. Missing values are invalid; `false` is an
-- explicit supported declaration meaning the capability is unavailable.
local capabilitySchema = {
    player = {
        identity = {
            character = 'boolean',
            account = 'boolean',
            license = 'boolean'
        },
        job = 'boolean',
        duty = 'boolean'
    },
    jobs = {
        multiple = 'boolean'
    },
    money = {
        cash = 'boolean',
        bank = 'boolean'
    },
    framework = {
        permissions = 'boolean'
    }
}

local requiredMethods = {
    'IsAvailable', 'Initialize', 'Shutdown', 'GetState',
    'GetPlayer', 'IsPlayerLoaded',
    'GetCharacterIdentifier', 'GetAccountIdentifier', 'GetLicense', 'GetCharacterName',
    'GetJob',
    'GetMoney', 'AddMoney', 'RemoveMoney',
    'SubscribePlayerLoaded', 'SubscribePlayerUnloaded', 'SubscribeJobChanged', 'SubscribeDutyChanged'
}

local function validateCapabilities(value, path, seen)
    if type(value) ~= 'table' then
        return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER, 'Framework capabilities must be a table', { path = path })
    end
    seen = seen or {}
    if seen[value] then
        return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER, 'Framework capabilities cannot contain cycles', { path = path })
    end
    seen[value] = true
    for key, item in pairs(value) do
        if type(key) ~= 'string' then
            return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER, 'Framework capability keys must be strings', { path = path })
        end
        if type(item) == 'table' then
            local ok, err = validateCapabilities(item, path .. '.' .. key, seen)
            if not ok then return false, err end
        elseif type(item) ~= 'boolean' then
            return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER, 'Framework capability values must be booleans', {
                path = path .. '.' .. key, actualType = type(item)
            })
        end
    end
    seen[value] = nil
    return true, nil
end

function FrameworkContract.Validate(adapter)
    if type(adapter) ~= 'table' then
        return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER, 'Framework adapter must be a table')
    end
    if type(adapter.metadata) ~= 'table' then
        return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER, 'Framework adapter metadata is missing')
    end

    local ok, err = Validation.String(adapter.metadata.name, {
        name = 'framework adapter name', nonEmpty = true, min = 1, max = 32,
        pattern = '^[%w_%-]+$'
    })
    if not ok then return false, Errors.Wrap(Codes.INVALID_FRAMEWORK_ADAPTER, 'Invalid framework adapter name', err) end

    ok, err = Validation.String(adapter.metadata.resource, {
        name = 'framework adapter resource', nonEmpty = true, min = 1, max = 128,
        pattern = '^[%w%._%-]+$'
    })
    if not ok then return false, Errors.Wrap(Codes.INVALID_FRAMEWORK_ADAPTER, 'Invalid framework adapter resource', err, { adapter = adapter.metadata.name }) end

    if adapter.metadata.version ~= nil then
        ok, err = Validation.String(tostring(adapter.metadata.version), {
            name = 'framework adapter version', nonEmpty = true, min = 1, max = 64
        })
        if not ok then return false, Errors.Wrap(Codes.INVALID_FRAMEWORK_ADAPTER, 'Invalid framework adapter version', err, { adapter = adapter.metadata.name }) end
    end

    ok, err = validateCapabilities(adapter.metadata.capabilities, 'capabilities')
    if not ok then return false, err end

    local function validateRequired(node, schema, path)
        for key, expected in pairs(schema) do
            local nextPath = path == '' and key or (path .. '.' .. key)
            if type(expected) == 'table' then
                if type(node[key]) ~= 'table' then
                    return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER,
                        'Framework adapter is missing a required capability group', {
                            adapter = adapter.metadata.name, capability = nextPath
                        })
                end
                local requiredOk, requiredErr = validateRequired(node[key], expected, nextPath)
                if not requiredOk then return false, requiredErr end
            elseif expected == 'boolean' and type(node[key]) ~= 'boolean' then
                return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER,
                    'Framework adapter is missing a required boolean capability declaration', {
                        adapter = adapter.metadata.name, capability = nextPath, actualType = type(node[key])
                    })
            end
        end
        return true, nil
    end

    ok, err = validateRequired(adapter.metadata.capabilities, capabilitySchema, '')
    if not ok then return false, err end

    local caps = adapter.metadata.capabilities
    if caps.player.duty and not caps.player.job then
        return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER,
            'Framework adapter cannot declare duty support without normalized job support', {
                adapter = adapter.metadata.name, capability = 'player.duty'
            })
    end
    if caps.jobs.multiple and not caps.player.job then
        return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER,
            'Framework adapter cannot declare multi-job capability without normalized primary job support', {
                adapter = adapter.metadata.name, capability = 'jobs.multiple'
            })
    end
    if (caps.money.cash or caps.money.bank) and (type(adapter.GetMoney) ~= 'function' or type(adapter.AddMoney) ~= 'function' or type(adapter.RemoveMoney) ~= 'function') then
        return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER,
            'Framework adapter declares money support without complete money methods', {
                adapter = adapter.metadata.name, capability = 'money'
            })
    end
    if caps.framework.permissions and type(adapter.HasFrameworkPermission) ~= 'function' then
        return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER,
            'Framework adapter declares permission support without HasFrameworkPermission', {
                adapter = adapter.metadata.name, capability = 'framework.permissions'
            })
    end

    local missing = {}
    for _, method in ipairs(requiredMethods) do
        if type(adapter[method]) ~= 'function' then missing[#missing + 1] = method end
    end
    if #missing > 0 then
        return false, Errors.Create(Codes.INVALID_FRAMEWORK_ADAPTER, 'Framework adapter contract is incomplete', {
            adapter = adapter.metadata.name, missing = missing
        })
    end

    return true, nil
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end

function FrameworkContract.CapabilitySchema()
    return copy(capabilitySchema)
end

function FrameworkContract.RequiredMethods()
    local out = {}
    for i, name in ipairs(requiredMethods) do out[i] = name end
    return out
end

NEXM_INTERNAL.Modules.FrameworkContract = FrameworkContract
