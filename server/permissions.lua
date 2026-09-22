local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local Logger = NEXM_INTERNAL.Modules.Logger
local Ownership = NEXM_INTERNAL.Modules.Ownership
local RegistryBase = NEXM_INTERNAL.Modules.RegistryBase
local Player = NEXM_INTERNAL.Modules.Player
local Jobs = NEXM_INTERNAL.Modules.Jobs
local Framework = NEXM_INTERNAL.Managers.Framework
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Callable = NEXM_INTERNAL.Modules.Callable

local Permissions = {}
local definitions = {}

local function q(owner, name) return owner .. ':' .. name end
local function validName(name)
    return Ownership.ValidateLocalName(name)
end
local function stringList(value, field)
    if value == nil then return true, nil, nil end
    if type(value) == 'string' then value = { value } end
    local ok, err = Validation.Table(value, { name = field, minEntries = 1, maxEntries = 64 }); if not ok then return false, err end
    local out = {}
    for i, item in ipairs(value) do
        ok, err = Validation.String(item, { name = field .. '[' .. i .. ']', nonEmpty = true, min = 1, max = 128, pattern = '^[%w%._:%-]+$' })
        if not ok then return false, err end
        out[#out + 1] = item
    end
    return true, nil, out
end

local function compile(policy)
    if type(policy) ~= 'table' then return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'Permission policy must be a table') end
    local mode = policy.mode or 'any'
    local ok, err = Validation.String(mode, { name = 'permission mode', allowed = { 'any', 'all' } }); if not ok then return nil, err end
    local out = { mode = mode }
    ok, err, out.ace = stringList(policy.ace, 'permission ace'); if not ok then return nil, err end
    ok, err, out.framework = stringList(policy.framework, 'framework permissions'); if not ok then return nil, err end

    if policy.jobs ~= nil then
        ok, err = Validation.Table(policy.jobs, { name = 'permission jobs', minEntries = 1, maxEntries = 64 }); if not ok then return nil, err end
        out.jobs = {}
        for jobName, rule in pairs(policy.jobs) do
            local nameOk, nameErr = Validation.String(jobName, { name = 'job name', nonEmpty = true, min = 1, max = 64, pattern = '^[%w_%-]+$' })
            if not nameOk then return nil, nameErr end
            if type(rule) ~= 'table' then return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'Job permission rule must be a table', { job = jobName }) end
            local grade = rule.minimumGrade or 0
            local gradeOk, gradeErr = Validation.Integer(grade, { name = 'minimumGrade', min = 0, max = 100000 }); if not gradeOk then return nil, gradeErr end
            local duty = rule.requireDuty == true
            if rule.requireDuty ~= nil and type(rule.requireDuty) ~= 'boolean' then return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'requireDuty must be boolean', { job = jobName }) end
            out.jobs[jobName] = { minimumGrade = grade, requireDuty = duty }
        end
    end
    if policy.custom ~= nil and not Callable.Is(policy.custom) then return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'Custom permission resolver must be callable') end
    out.custom = policy.custom
    if not out.ace and not out.jobs and not out.framework and not out.custom then
        return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'Permission policy must configure at least one provider')
    end
    return out, nil
end

function Permissions.Define(name, policy, ownerResource)
    local owner = ownerResource or Ownership.Resolve()
    local ok, err = validName(name); if not ok then return false, err end
    local key = q(owner, name)
    if definitions[key] then
        return false, Errors.Create(Codes.REGISTRATION_EXISTS, 'Permission definition already exists', { permission = name, ownerResource = owner })
    end
    local compiled, compileErr = compile(policy); if not compiled then return false, compileErr end
    definitions[key] = { name = name, ownerResource = owner, registeredAt = os.time(), policy = compiled }
    return true, nil
end

local function aceProvider(source, list)
    for _, permission in ipairs(list or {}) do if IsPlayerAceAllowed and IsPlayerAceAllowed(source, permission) then return true end end
    return false
end

local function jobProvider(source, rules)
    local job, err = Jobs.Get(source)
    if not job then return false, err end
    local rule = rules[job.name]
    if not rule or job.grade < rule.minimumGrade then return false, nil end
    if rule.requireDuty then
        local duty, dutyErr = Jobs.IsOnDuty(source)
        if dutyErr then
            if dutyErr.code == Codes.UNSUPPORTED_FEATURE then return false, nil end
            return false, dutyErr
        end
        if duty ~= true then return false, nil end
    end
    return true, nil
end

local function frameworkProvider(source, list)
    local adapter, err = Framework.RequireHealthy(); if not adapter then return false, err end
    local caps = adapter.metadata.capabilities
    if not (caps.framework and caps.framework.permissions == true) then
        return false, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Framework permission capability is unavailable', { feature = 'framework.permissions' })
    end
    if type(adapter.HasFrameworkPermission) ~= 'function' then
        return false, Errors.Create(Codes.ADAPTER_ERROR, 'Framework permission method is unavailable')
    end
    for _, permission in ipairs(list or {}) do
        local ok, allowed, callErr = pcall(adapter.HasFrameworkPermission, source, permission)
        if not ok then
            local e = Errors.Create(Codes.ADAPTER_ERROR, 'Framework permission check failed')
            Logger.Infrastructure(e, 'permissions:framework', 'nexm_core')
            return false, e
        end
        if callErr then return false, callErr end
        if allowed == true then return true, nil end
    end
    return false, nil
end

local function customProvider(source, resolver, owner)
    local snapshot, playerErr = Player.Get(source)
    if not snapshot then return false, playerErr end
    local context = RegistryBase.Copy({ source = source, ownerResource = owner, player = snapshot })
    local ok, result = pcall(resolver, source, context)
    if not ok then
        local err = Errors.Create(Codes.PERMISSION_RESOLVER_ERROR, 'Custom permission resolver failed', { ownerResource = owner })
        Logger.Infrastructure(err, 'permission:custom', owner)
        if Config and Config.Debug then Logger.Debug('Custom permission resolver raw error', { rawError = tostring(result) }, owner) end
        return false, err
    end
    return result == true, nil
end

function Permissions.Has(source, name, ownerResource)
    local sourceOk, sourceErr = Validation.Source(source); if not sourceOk then return false, sourceErr end
    local owner = ownerResource or Ownership.Resolve()
    local ok, nameErr = validName(name); if not ok then return false, nameErr end
    local definition = definitions[q(owner, name)]
    if not definition then
        if Config and Config.Debug then Logger.Warn('Permission is not defined', { ownerResource = owner, permission = name }, owner) end
        return false, Errors.Create(Codes.PERMISSION_NOT_DEFINED, 'Permission is not defined', { ownerResource = owner, permission = name })
    end

    local providers = {}
    if definition.policy.ace then providers[#providers + 1] = function() return aceProvider(source, definition.policy.ace), nil end end
    if definition.policy.jobs then providers[#providers + 1] = function() return jobProvider(source, definition.policy.jobs) end end
    if definition.policy.framework then providers[#providers + 1] = function() return frameworkProvider(source, definition.policy.framework) end end
    if definition.policy.custom then providers[#providers + 1] = function() return customProvider(source, definition.policy.custom, owner) end end

    if definition.policy.mode == 'all' then
        for _, provider in ipairs(providers) do
            local allowed, err = provider(); if err then return false, err end; if not allowed then return false, nil end
        end
        return true, nil
    end
    local firstError = nil
    for _, provider in ipairs(providers) do
        local allowed, err = provider()
        if allowed then return true, nil end
        if err and not firstError then firstError = err end
    end
    if firstError then return false, firstError end
    return false, nil
end

function Permissions.HasAny(source, names, ownerResource)
    local ok, err = Validation.Table(names, { name = 'permission names', minEntries = 1, maxEntries = 64 }); if not ok then return false, err end
    local firstError = nil
    for _, name in ipairs(names) do
        local allowed, permissionErr = Permissions.Has(source, name, ownerResource)
        if allowed then return true, nil end
        if permissionErr and not firstError then firstError = permissionErr end
    end
    if firstError then return false, firstError end
    return false, nil
end

function Permissions.CleanupOwner(ownerResource)
    local removed = 0
    local prefix = ownerResource .. ':'
    for key in pairs(definitions) do if key:sub(1, #prefix) == prefix then definitions[key] = nil; removed = removed + 1 end end
    return removed
end

function Permissions.Count() local n = 0; for _ in pairs(definitions) do n = n + 1 end; return n end

NEXM_INTERNAL.Modules.Permissions = Permissions
