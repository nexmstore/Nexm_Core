local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local Ownership = {}

local function sanitizeOwner(owner)
    local ok = type(owner) == 'string' and owner:match('^[%w%._%-]+$') ~= nil
    if ok then
        return owner
    end
    return nil
end

function Ownership.Resolve(fallback)
    local invoking = GetInvokingResource and GetInvokingResource() or nil
    invoking = sanitizeOwner(invoking)
    if invoking then
        return invoking
    end

    local current = GetCurrentResourceName and GetCurrentResourceName() or nil
    current = sanitizeOwner(current)
    if current then
        return current
    end

    return sanitizeOwner(fallback) or 'nexm_core'
end

function Ownership.ValidateLocalName(name)
    local ok, err = Validation.String(name, {
        name = 'registration name',
        nonEmpty = true,
        min = 1,
        max = 128,
        pattern = '^[%w%._%-]+$'
    })

    if not ok then
        return false, err
    end

    return true, nil
end

function Ownership.Qualify(ownerResource, localName)
    local owner = sanitizeOwner(ownerResource)
    if not owner then
        return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'Invalid owner resource', { ownerResource = ownerResource })
    end

    local ok, err = Ownership.ValidateLocalName(localName)
    if not ok then
        return nil, err
    end

    return owner .. ':' .. localName, nil
end

function Ownership.NewMetadata(ownerResource, metadata)
    return {
        ownerResource = ownerResource,
        registeredAt = os.time(),
        metadata = type(metadata) == 'table' and metadata or {}
    }
end

NEXM_INTERNAL.Modules.Ownership = Ownership
