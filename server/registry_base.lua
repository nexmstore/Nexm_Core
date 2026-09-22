local Errors = NEXM_INTERNAL.Modules.Errors
local Ownership = NEXM_INTERNAL.Modules.Ownership
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Callable = NEXM_INTERNAL.Modules.Callable

local RegistryBase = {}
RegistryBase.__index = RegistryBase

local function copy(value, seen)
    if Callable.Is(value) then return value end
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return '<cycle>' end
    seen[value] = true
    local out = {}
    for key, item in pairs(value) do out[copy(key, seen)] = copy(item, seen) end
    seen[value] = nil
    return out
end

local function readonly(value, seen)
    if Callable.Is(value) then return value end
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local proxy = {}
    seen[value] = proxy
    setmetatable(proxy, {
        __index = function(_, key) return readonly(value[key], seen) end,
        __newindex = function() error('NEXM read-only service facade cannot be modified', 2) end,
        __len = function() return #value end,
        __pairs = function()
            local function iterator(_, previous)
                local key, item = next(value, previous)
                if key ~= nil then return key, readonly(item, seen) end
            end
            return iterator, value, nil
        end,
        __metatable = false
    })
    return proxy
end

function RegistryBase.Copy(value) return copy(value) end
function RegistryBase.ReadOnly(value) return readonly(value, {}) end

function RegistryBase.New(name)
    return setmetatable({ name = name, records = {}, publicIndex = {} }, RegistryBase)
end

function RegistryBase:Register(publicKey, value, metadata, ownerResource)
    local owner = ownerResource or Ownership.Resolve()
    local validName, nameErr = Ownership.ValidateLocalName(publicKey)
    if not validName then return false, nameErr end

    local internalKey, keyErr = Ownership.Qualify(owner, publicKey)
    if not internalKey then return false, keyErr end

    local existingKey = self.publicIndex[publicKey]
    if existingKey then
        local existing = self.records[existingKey]
        if existing and existing.ownerResource ~= owner then
            return false, Errors.Create(Codes.REGISTRATION_CONFLICT,
                ('%s registration is owned by another resource'):format(self.name), {
                    registry = self.name,
                    name = publicKey,
                    ownerResource = owner,
                    existingOwnerResource = existing.ownerResource
                })
        end
        return false, Errors.Create(Codes.REGISTRATION_EXISTS,
            ('%s registration already exists'):format(self.name), {
                registry = self.name, name = publicKey, ownerResource = owner
            })
    end

    self.records[internalKey] = {
        name = publicKey,
        internalKey = internalKey,
        ownerResource = owner,
        registeredAt = os.time(),
        metadata = type(metadata) == 'table' and copy(metadata) or {},
        value = value
    }
    self.publicIndex[publicKey] = internalKey
    return true, self.records[internalKey]
end

function RegistryBase:GetRecord(publicKey)
    local internalKey = self.publicIndex[publicKey]
    return internalKey and self.records[internalKey] or nil
end
function RegistryBase:GetValue(publicKey)
    local record = self:GetRecord(publicKey)
    return record and record.value or nil
end
function RegistryBase:Has(publicKey) return self:GetRecord(publicKey) ~= nil end
function RegistryBase:RemoveOwned(ownerResource)
    local removed = 0
    for internalKey, record in pairs(self.records) do
        if record.ownerResource == ownerResource then
            self.publicIndex[record.name] = nil
            self.records[internalKey] = nil
            removed = removed + 1
        end
    end
    return removed
end
function RegistryBase:Count()
    local count = 0
    for _ in pairs(self.records) do count = count + 1 end
    return count
end
function RegistryBase:ListMetadata()
    local out = {}
    for _, record in pairs(self.records) do
        out[#out + 1] = {
            name = record.name,
            ownerResource = record.ownerResource,
            registeredAt = record.registeredAt,
            metadata = copy(record.metadata)
        }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

NEXM_INTERNAL.Modules.RegistryBase = RegistryBase
