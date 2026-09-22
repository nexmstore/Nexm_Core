local RegistryBase = NEXM_INTERNAL.Modules.RegistryBase
local Ownership = NEXM_INTERNAL.Modules.Ownership

local Features = {}
local registry = RegistryBase.New('feature')
local copy = RegistryBase.Copy

function Features.Register(name, value, metadata, ownerResource)
    local owner = ownerResource or Ownership.Resolve()
    local ok, recordOrErr = registry:Register(name, value == nil and true or value, metadata or {}, owner)
    if not ok then return false, recordOrErr end
    return true, nil
end

function Features.Has(name)
    return registry:Has(name)
end

function Features.Get(name)
    return registry:GetValue(name)
end

function Features.GetMetadata(name)
    local record = registry:GetRecord(name)
    if not record then return nil end
    return {
        name = record.name,
        ownerResource = record.ownerResource,
        registeredAt = record.registeredAt,
        metadata = copy(record.metadata)
    }
end

function Features.Count() return registry:Count() end
function Features.ListMetadata() return registry:ListMetadata() end
function Features.CleanupOwner(ownerResource) return registry:RemoveOwned(ownerResource) end

NEXM_INTERNAL.Managers.Features = Features
