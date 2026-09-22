local RegistryBase = NEXM_INTERNAL.Modules.RegistryBase
local Ownership = NEXM_INTERNAL.Modules.Ownership
local Validation = NEXM_INTERNAL.Modules.Validation
local SemVer = NEXM_INTERNAL.Modules.SemVer
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local CoreVersion = NEXM_INTERNAL.Modules.Constants.VERSION
local State = NEXM_INTERNAL.Modules.State
local Health = NEXM_INTERNAL.Modules.Constants.HEALTH

local Resources = {}
local registry = RegistryBase.New('resource')
local copy = RegistryBase.Copy

local function capabilityValue(tree, path)
    local node = tree
    for part in tostring(path):gmatch('[^%.]+') do
        if type(node) ~= 'table' then return nil end
        node = node[part]
    end
    return node
end

local function capabilityList(value, field)
    if value == nil then return true, nil, {} end
    local ok, err = Validation.Table(value, { name = field, maxEntries = 64 }); if not ok then return false, err end
    local out = {}
    for i, path in ipairs(value) do
        ok, err = Validation.String(path, { name = field .. '[' .. i .. ']', nonEmpty = true, min = 1, max = 128, pattern = '^[%w_%-]+[%w%._%-]*$' })
        if not ok then return false, err end
        out[#out + 1] = path
    end
    return true, nil, out
end

local function normalizeRequirements(value)
    if value == nil then return {}, nil end
    if type(value) ~= 'table' then return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'Resource requirements must be a table') end
    local out = {}
    if value.framework ~= nil then
        local ok, err = Validation.Boolean(value.framework, { name = 'requirements.framework' }); if not ok then return nil, err end
        out.framework = value.framework
    end
    local ok, err, list = capabilityList(value.frameworkCapabilities, 'requirements.frameworkCapabilities')
    if not ok then return nil, err end
    if #list > 0 then out.frameworkCapabilities = list end

    if value.integrations ~= nil then
        ok, err = Validation.Table(value.integrations, { name = 'requirements.integrations', maxEntries = 32 }); if not ok then return nil, err end
        out.integrations = {}
        for category, definition in pairs(value.integrations) do
            local categoryOk, categoryErr = Ownership.ValidateLocalName(category); if not categoryOk then return nil, categoryErr end
            if type(definition) ~= 'table' then return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'Integration requirement must be a table', { category = category }) end
            local required = definition.required == true
            if definition.required ~= nil and type(definition.required) ~= 'boolean' then return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'Integration requirement required must be boolean', { category = category }) end
            local capOk, capErr, caps = capabilityList(definition.capabilities, 'requirements.integrations.' .. category .. '.capabilities')
            if not capOk then return nil, capErr end
            out.integrations[category] = { required = required, capabilities = caps }
        end
    end
    return out, nil
end

function Resources.ValidateRequirements(requirements)
    requirements = requirements or {}
    local Framework = NEXM_INTERNAL.Managers.Framework
    local Integrations = NEXM_INTERNAL.Managers.Integrations
    if requirements.framework == true then
        local component = State.GetComponent('framework')
        if not component or component.state ~= Health.HEALTHY then
            return false, Errors.Create(Codes.DEPENDENCY_UNAVAILABLE, 'Required framework is unavailable', { dependency = 'framework' })
        end
    end
    if requirements.frameworkCapabilities then
        local caps = Framework and Framework.GetCapabilities and Framework.GetCapabilities() or nil
        if not caps then return false, Errors.Create(Codes.DEPENDENCY_UNAVAILABLE, 'Framework capabilities are unavailable', { dependency = 'framework' }) end
        for _, path in ipairs(requirements.frameworkCapabilities) do
            if capabilityValue(caps, path) ~= true then
                return false, Errors.Create(Codes.CAPABILITY_UNAVAILABLE, 'Required framework capability is unavailable', { dependency = 'framework', capability = path })
            end
        end
    end
    for category, definition in pairs(requirements.integrations or {}) do
        local component = State.GetComponent(category)
        local selected = Integrations and Integrations.GetSelected and Integrations.GetSelected(category) or nil
        local available = component and component.state == Health.HEALTHY and selected ~= nil
        if definition.required and not available then
            return false, Errors.Create(Codes.DEPENDENCY_UNAVAILABLE, 'Required integration is unavailable', {
                dependency = category, componentState = component and component.state or Health.NOT_INITIALIZED
            })
        end
        if #definition.capabilities > 0 then
            if not available then return false, Errors.Create(Codes.DEPENDENCY_UNAVAILABLE, 'Integration required for capability check is unavailable', { dependency = category }) end
            local caps = Integrations.GetCapabilities(category, selected) or {}
            for _, path in ipairs(definition.capabilities) do
                if capabilityValue(caps, path) ~= true then
                    return false, Errors.Create(Codes.CAPABILITY_UNAVAILABLE, 'Required integration capability is unavailable', { dependency = category, capability = path, integration = selected })
                end
            end
        end
    end
    return true, nil
end

function Resources.Register(metadata, ownerResource)
    metadata = type(metadata) == 'table' and metadata or {}
    local owner = ownerResource or Ownership.Resolve()
    if metadata.name and metadata.name ~= owner then
        return false, Errors.Create(Codes.OWNER_MISMATCH, 'Resource metadata name does not match actual invoking resource', { ownerResource = owner, requestedName = metadata.name })
    end
    local version = metadata.version or '0.0.0'
    local parsedVersion, versionErr = SemVer.Parse(version); if not parsedVersion then return false, versionErr end
    local requirement = metadata.requiresCore or '>=1.0.0'
    local compatible, requirementErr = SemVer.Satisfies(CoreVersion, requirement); if requirementErr then return false, requirementErr end
    if not compatible then return false, Errors.Create(Codes.INCOMPATIBLE_CORE_VERSION, 'Resource requires an incompatible NEXM Core version', { resource = owner, installed = CoreVersion, required = requirement }) end
    local requirements, requirementsErr = normalizeRequirements(metadata.requirements); if not requirements then return false, requirementsErr end
    local requirementsOk, dependencyErr = Resources.ValidateRequirements(requirements)
    if not requirementsOk then return false, dependencyErr end
    local ok, recordOrErr = registry:Register(owner, true, {
        version = version, requiresCore = requirement, state = 'ACTIVE', requirements = requirements, lastDependencyError = nil
    }, owner)
    if not ok then return false, recordOrErr end
    return true, nil
end

function Resources.Get(name)
    local record = registry:GetRecord(name); if not record then return nil end
    return {
        name = record.name, ownerResource = record.ownerResource, registeredAt = record.registeredAt,
        version = record.metadata.version, requiresCore = record.metadata.requiresCore, state = record.metadata.state,
        requirements = copy(record.metadata.requirements or {}),
        lastDependencyError = record.metadata.lastDependencyError and Errors.Copy(record.metadata.lastDependencyError) or nil
    }
end

function Resources.IsRunning(name)
    local record = registry:GetRecord(name); if not record then return false end
    if GetResourceState then return GetResourceState(name) == 'started' end
    return true
end
function Resources.GetAll() local out={}; for _,item in ipairs(registry:ListMetadata()) do out[#out+1]=Resources.Get(item.name) end; return out end

function Resources.RevalidateAll(reason)
    local EventBus = NEXM_INTERNAL.Modules.EventBus
    local changed = 0
    for _, item in ipairs(registry:ListMetadata()) do
        local record = registry:GetRecord(item.name)
        local ok, err = Resources.ValidateRequirements(record.metadata.requirements or {})
        local nextState = ok and 'ACTIVE' or 'DEGRADED'
        if record.metadata.state ~= nextState or ((record.metadata.lastDependencyError and record.metadata.lastDependencyError.code) ~= (err and err.code)) then
            record.metadata.state = nextState
            record.metadata.lastDependencyError = err and Errors.Copy(err) or nil
            changed = changed + 1
            if EventBus and EventBus.Emit then EventBus.Emit('core:resourceDependencyChanged', { resource = record.name, state = nextState, reason = reason, errorCode = err and err.code or nil }) end
        end
    end
    return changed
end

function Resources.NotifyComponentChanged(component, state)
    local EventBus = NEXM_INTERNAL.Modules.EventBus
    if EventBus and EventBus.Emit then EventBus.Emit('core:componentStateChanged', { component = component, state = state }) end
    Resources.RevalidateAll(component .. ':' .. tostring(state))
end


local function appendCheck(checks, name, ok, detail)
    checks[#checks + 1] = { name = name, ok = ok == true, detail = detail }
end

function Resources.EvaluateRequirements(requirements)
    requirements = requirements or {}
    local Framework = NEXM_INTERNAL.Managers.Framework
    local Integrations = NEXM_INTERNAL.Managers.Integrations
    local checks, overall = {}, true
    if requirements.framework == true then
        local c = State.GetComponent('framework'); local ok = c and c.state == Health.HEALTHY
        appendCheck(checks, 'framework', ok, c and c.state or Health.NOT_INITIALIZED); overall = overall and ok
    end
    if requirements.frameworkCapabilities then
        local caps = Framework and Framework.GetCapabilities and Framework.GetCapabilities() or {}
        for _, path in ipairs(requirements.frameworkCapabilities) do
            local ok = capabilityValue(caps, path) == true
            appendCheck(checks, 'framework.' .. path, ok, ok and 'SUPPORTED' or 'UNAVAILABLE'); overall = overall and ok
        end
    end
    for category, definition in pairs(requirements.integrations or {}) do
        local c = State.GetComponent(category); local selected = Integrations and Integrations.GetSelected and Integrations.GetSelected(category) or nil
        local available = c and c.state == Health.HEALTHY and selected ~= nil
        if definition.required then appendCheck(checks, category, available, c and c.state or Health.NOT_INITIALIZED); overall = overall and available end
        local caps = available and (Integrations.GetCapabilities(category, selected) or {}) or {}
        for _, path in ipairs(definition.capabilities or {}) do
            local ok = available and capabilityValue(caps, path) == true
            appendCheck(checks, category .. '.' .. path, ok, ok and 'SUPPORTED' or 'UNAVAILABLE'); overall = overall and ok
        end
    end
    return overall, checks
end

function Resources.GetRequirementStatus(name)
    local record = registry:GetRecord(name); if not record then return nil end
    local ok, checks = Resources.EvaluateRequirements(record.metadata.requirements or {})
    return { resource = name, state = record.metadata.state, ok = ok, checks = copy(checks),
        lastDependencyError = record.metadata.lastDependencyError and Errors.Copy(record.metadata.lastDependencyError) or nil }
end

function Resources.Count() return registry:Count() end
function Resources.CleanupOwner(ownerResource) return registry:RemoveOwned(ownerResource) end
NEXM_INTERNAL.Managers.Resources = Resources
