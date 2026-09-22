local Errors = NEXM_INTERNAL.Modules.Errors
local Validation = NEXM_INTERNAL.Modules.Validation
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local Contract = {}
local capabilitySchema = {
    metadata = 'boolean',
    metadataFilter = 'boolean',
    canCarry = 'boolean',
    getItems = 'boolean'
}
local requiredMethods = {
    'IsAvailable', 'Initialize', 'Shutdown', 'GetState',
    'HasItem', 'GetItemCount', 'AddItem', 'RemoveItem', 'CanCarry'
}

local function validateCapabilities(caps)
    if type(caps) ~= 'table' then
        return false, Errors.Create(Codes.INVALID_INVENTORY_ADAPTER, 'Inventory capabilities must be a table')
    end
    for key, expected in pairs(capabilitySchema) do
        if type(caps[key]) ~= expected then
            return false, Errors.Create(Codes.INVALID_INVENTORY_ADAPTER,
                'Inventory adapter is missing a required boolean capability declaration', {
                    capability = key, actualType = type(caps[key])
                })
        end
    end
    for key, value in pairs(caps) do
        if type(key) ~= 'string' or type(value) ~= 'boolean' then
            return false, Errors.Create(Codes.INVALID_INVENTORY_ADAPTER,
                'Inventory capability values must be booleans', { capability = tostring(key), actualType = type(value) })
        end
    end
    return true, nil
end

function Contract.Validate(adapter)
    if type(adapter) ~= 'table' or type(adapter.metadata) ~= 'table' then
        return false, Errors.Create(Codes.INVALID_INVENTORY_ADAPTER, 'Inventory adapter metadata is missing')
    end
    local ok, err = Validation.String(adapter.metadata.name, {
        name = 'inventory adapter name', nonEmpty = true, min = 1, max = 64, pattern = '^[%w_%-]+$'
    })
    if not ok then return false, Errors.Wrap(Codes.INVALID_INVENTORY_ADAPTER, 'Invalid inventory adapter name', err) end
    ok, err = Validation.String(adapter.metadata.resource, {
        name = 'inventory adapter resource', nonEmpty = true, min = 1, max = 128, pattern = '^[%w%._%-]+$'
    })
    if not ok then return false, Errors.Wrap(Codes.INVALID_INVENTORY_ADAPTER, 'Invalid inventory adapter resource', err) end
    if adapter.metadata.critical ~= true then
        return false, Errors.Create(Codes.INVALID_INVENTORY_ADAPTER, 'Inventory adapters must declare critical=true', {
            adapter = adapter.metadata.name
        })
    end
    ok, err = validateCapabilities(adapter.metadata.capabilities)
    if not ok then return false, err end
    local missing = {}
    for _, method in ipairs(requiredMethods) do
        if type(adapter[method]) ~= 'function' then missing[#missing + 1] = method end
    end
    if adapter.metadata.capabilities.getItems and type(adapter.GetItems) ~= 'function' then
        missing[#missing + 1] = 'GetItems'
    end
    if #missing > 0 then
        return false, Errors.Create(Codes.INVALID_INVENTORY_ADAPTER, 'Inventory adapter contract is incomplete', {
            adapter = adapter.metadata.name, missing = missing
        })
    end
    -- Semantic claims that share the base methods are verified by adapter-specific
    -- regression tests. Syntactically, metadataFilter requires query/remove methods,
    -- all of which are mandatory above; no separate fake method is invented.
    return true, nil
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end
function Contract.CapabilitySchema() return copy(capabilitySchema) end
function Contract.RequiredMethods() local out={}; for i,v in ipairs(requiredMethods) do out[i]=v end; return out end

NEXM_INTERNAL.Modules.InventoryContract = Contract
