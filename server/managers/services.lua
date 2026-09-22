local RegistryBase = NEXM_INTERNAL.Modules.RegistryBase
local Ownership = NEXM_INTERNAL.Modules.Ownership
local SemVer = NEXM_INTERNAL.Modules.SemVer
local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local Services = {}
local registry = RegistryBase.New('service')
local copy = RegistryBase.Copy

local function normalizeOptions(metadata)
    metadata = type(metadata) == 'table' and metadata or {}
    local version = metadata.version or '0.0.0'
    local parsed, versionErr = SemVer.Parse(version)
    if not parsed then return nil, versionErr end
    local ok, apiErr = Validation.Integer(metadata.apiVersion or 1, { name='service apiVersion', min=1, max=100000 })
    if not ok then return nil, apiErr end
    local capabilities = type(metadata.capabilities)=='table' and metadata.capabilities or {}
    return { version=version, apiVersion=metadata.apiVersion or 1, capabilities=capabilities },nil
end

function Services.Register(name, api, metadata, ownerResource)
    local owner=ownerResource or Ownership.Resolve()
    if type(api)~='table' then return false,Errors.Create(Codes.INVALID_ARGUMENT,'Service API must be a table',{name=name}) end
    local normalized,err=normalizeOptions(metadata); if not normalized then return false,err end
    local ok,recordOrErr=registry:Register(name,api,normalized,owner)
    if not ok then return false,recordOrErr end
    return true,nil
end

local function compatible(record, options)
    if not record then return false,Errors.Create(Codes.SERVICE_UNAVAILABLE,'Service is unavailable') end
    if options and options.apiVersion~=nil then
        local ok,err=Validation.Integer(options.apiVersion,{name='required service apiVersion',min=1,max=100000}); if not ok then return false,err end
        if record.metadata.apiVersion~=options.apiVersion then
            return false,Errors.Create(Codes.SERVICE_API_VERSION_MISMATCH,'Service API version does not match requirement',{
                service=record.name,required=options.apiVersion,available=record.metadata.apiVersion
            })
        end
    end
    return true,nil
end

function Services.Get(name, options)
    local record=registry:GetRecord(name)
    local ok,err=compatible(record,options); if not ok then return nil,err end
    -- A metatable-only read-only proxy loses its fields when serialized across a
    -- FiveM function-reference boundary. Return a deep snapshot instead: external
    -- consumers can mutate their local copy, but cannot mutate the authoritative
    -- registered service. Callable Cfx function refs are preserved by Copy().
    return copy(record.value),nil
end

function Services.Has(name, options)
    local record=registry:GetRecord(name)
    if not record then return false,nil end
    local ok,err=compatible(record,options); if not ok then return false,err end
    return true,nil
end

function Services.GetMetadata(name)
    local record=registry:GetRecord(name); if not record then return nil end
    return {name=record.name,ownerResource=record.ownerResource,registeredAt=record.registeredAt,
        version=record.metadata.version,apiVersion=record.metadata.apiVersion,capabilities=copy(record.metadata.capabilities)}
end
function Services.Count() return registry:Count() end
function Services.ListMetadata() return registry:ListMetadata() end
function Services.CleanupOwner(ownerResource) return registry:RemoveOwned(ownerResource) end
NEXM_INTERNAL.Managers.Services=Services
