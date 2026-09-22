local Contract = NEXM_INTERNAL.Modules.FrameworkContract
local Errors = NEXM_INTERNAL.Modules.Errors
local Logger = NEXM_INTERNAL.Modules.Logger
local State = NEXM_INTERNAL.Modules.State
local Constants = NEXM_INTERNAL.Modules.Constants
local Codes, Health, States = Constants.ERROR_CODES, Constants.HEALTH, Constants.STATES

local Framework = {}
local adapters = {}
local selectedName, selectedAdapter = nil, nil
local monitorInstalled = false

local supportedResources = {
    esx = 'es_extended',
    qbcore = 'qb-core',
    qbox = 'qbx_core'
}

local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return '<cycle>' end
    seen[value] = true
    local out = {}
    for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
    seen[value] = nil
    return out
end

local function isStarted(resource)
    return GetResourceState and GetResourceState(resource) == 'started'
end

-- Qbox declares `provide 'qb-core'`. On current FiveM a provider can act as the
-- provided resource. Comparing resolved resource paths prevents a qbx_core-only
-- installation from being counted twice when the qb-core name resolves to the
-- same provider. If the runtime cannot prove aliasing, ambiguity fails closed.
local function isProvidedAlias(aliasName, providerName)
    if not isStarted(aliasName) or not isStarted(providerName) then return false end
    if GetResourcePath then
        local okA, aliasPath = pcall(GetResourcePath, aliasName)
        local okP, providerPath = pcall(GetResourcePath, providerName)
        if okA and okP and type(aliasPath) == 'string' and aliasPath ~= '' and aliasPath == providerPath then
            return true
        end
    end
    if GetResourceMetadata then
        local ok, declaredName = pcall(GetResourceMetadata, aliasName, 'name', 0)
        if ok and declaredName == providerName then return true end
    end
    return false
end

function Framework.RegisterBuiltinAdapters()
    adapters = {}
    for name, adapter in pairs(NEXM_INTERNAL.Adapters.Framework or {}) do adapters[name] = adapter end
    return true, nil
end

function Framework.GetAdapter(name) return adapters[name] end

function Framework.DetectCandidates()
    local candidates = {}
    if isStarted('es_extended') then candidates[#candidates + 1] = 'esx' end
    if isStarted('qbx_core') then candidates[#candidates + 1] = 'qbox' end
    if isStarted('qb-core') and not isProvidedAlias('qb-core', 'qbx_core') then candidates[#candidates + 1] = 'qbcore' end
    table.sort(candidates)
    return candidates
end

local function contains(list, value)
    for _, item in ipairs(list or {}) do if item == value then return true end end
    return false
end

function Framework.ResolveSelection(configured, priority)
    configured = configured or 'auto'
    if configured == 'standalone' then return 'standalone', nil end

    local candidates = Framework.DetectCandidates()
    if configured ~= 'auto' then
        if not contains(candidates, configured) then
            return nil, Errors.Create(Codes.FRAMEWORK_UNAVAILABLE, 'Configured framework is not available', {
                configured = configured, detected = candidates, resource = supportedResources[configured]
            })
        end
        return configured, nil
    end

    if #candidates == 0 then
        if Config and Config.FrameworkAutoStandalone == true then return 'standalone', nil end
        return nil, Errors.Create(Codes.FRAMEWORK_UNAVAILABLE, 'No supported framework is active and automatic standalone fallback is disabled', {
            detected = candidates
        })
    end
    if #candidates == 1 then return candidates[1], nil end

    if type(priority) == 'table' and #priority > 0 then
        for _, name in ipairs(priority) do
            if contains(candidates, name) then return name, nil end
        end
    end

    return nil, Errors.Create(Codes.AMBIGUOUS_FRAMEWORK_INTEGRATION,
        'Multiple active frameworks were detected and no explicit priority resolved the ambiguity', {
            detected = candidates
        })
end

local function componentDetails(adapter)
    return {
        name = adapter.metadata.name,
        resource = adapter.metadata.resource,
        version = adapter.metadata.version,
        capabilities = copy(adapter.metadata.capabilities)
    }
end

function Framework.InitializeSelected()
    if not next(adapters) then Framework.RegisterBuiltinAdapters() end

    local name, selectErr = Framework.ResolveSelection(Config.Framework, Config.FrameworkPriority)
    if not name then
        State.SetComponent('framework', Health.UNAVAILABLE, { error = selectErr })
        Logger.Infrastructure(selectErr, 'framework', 'nexm_core')
        return false, selectErr
    end

    if selectedName and selectedName ~= name then
        local err = Errors.Create(Codes.INTEGRATION_SELECTION_LOCKED, 'Framework selection is sticky after successful initialization', {
            selected = selectedName, requested = name
        })
        Logger.Infrastructure(err, 'framework', 'nexm_core')
        return false, err
    end

    local adapter = adapters[name]
    local valid, contractErr = Contract.Validate(adapter)
    if not valid then
        State.SetComponent('framework', Health.FAILED, { name = name, error = contractErr })
        Logger.Infrastructure(contractErr, 'framework', 'nexm_core')
        return false, contractErr
    end

    local availableOk, available = pcall(adapter.IsAvailable)
    if not availableOk or available ~= true then
        local err = Errors.Create(Codes.FRAMEWORK_UNAVAILABLE, 'Selected framework adapter is not available', {
            framework = name, resource = adapter.metadata.resource
        })
        State.SetComponent('framework', Health.UNAVAILABLE, { name = name, error = err })
        Logger.Infrastructure(err, 'framework', 'nexm_core')
        return false, err
    end

    local initCallOk, initOk, initErr = pcall(adapter.Initialize)
    if not initCallOk or initOk ~= true then
        local err = Errors.Is(initErr) and initErr or Errors.Create(Codes.FRAMEWORK_INITIALIZATION_FAILED,
            'Framework adapter initialization failed', { framework = name })
        State.SetComponent('framework', Health.FAILED, { name = name, error = err })
        Logger.Infrastructure(err, 'framework', 'nexm_core')
        return false, err
    end

    selectedName, selectedAdapter = name, adapter
    State.SetComponent('framework', Health.HEALTHY, componentDetails(adapter))
    local moneyCaps = adapter.metadata.capabilities.money or {}
    State.SetComponent('money', (moneyCaps.cash or moneyCaps.bank) and Health.HEALTHY or Health.UNAVAILABLE, { framework = name, capabilities = copy(moneyCaps) })
    Logger.Info('Framework initialized', componentDetails(adapter), 'nexm_core')
    return true, nil
end

function Framework.GetName() return selectedName end
function Framework.GetSelected() return selectedAdapter end
function Framework.GetCapabilities()
    return selectedAdapter and copy(selectedAdapter.metadata.capabilities) or nil
end
function Framework.GetMetadata()
    return selectedAdapter and componentDetails(selectedAdapter) or nil
end
function Framework.IsHealthy()
    local component = State.GetComponent('framework')
    return selectedAdapter ~= nil and component and component.state == Health.HEALTHY
end
function Framework.RequireHealthy()
    if Framework.IsHealthy() then return selectedAdapter, nil end
    local err = Errors.Create(Codes.FRAMEWORK_UNAVAILABLE, 'Active framework is unavailable', {
        framework = selectedName,
        coreState = State.Get()
    })
    Logger.Infrastructure(err, 'framework', 'nexm_core')
    return nil, err
end

local function degrade(reason)
    if not selectedAdapter then return end
    pcall(selectedAdapter.Shutdown)
    State.SetComponent('framework', Health.UNAVAILABLE, {
        name = selectedName, resource = selectedAdapter.metadata.resource, reason = reason
    })
    State.SetComponent('money', Health.UNAVAILABLE, { framework = selectedName, reason = reason })
    if State.Get() == States.READY then State.Set(States.DEGRADED) end

    local err = Errors.Create(Codes.FRAMEWORK_UNAVAILABLE, 'Active framework stopped during runtime', {
        framework = selectedName, resource = selectedAdapter.metadata.resource, reason = reason
    })
    Logger.Infrastructure(err, 'framework', 'nexm_core')
    local Lifecycle = NEXM_INTERNAL.Modules.Lifecycle
    if Lifecycle and Lifecycle.FrameworkUnavailable then Lifecycle.FrameworkUnavailable(err) end
    TriggerEvent('nexm_core:server:frameworkDegraded', selectedName, Errors.Copy(err))
    local EventBus = NEXM_INTERNAL.Modules.EventBus
    if EventBus and EventBus.Emit then EventBus.Emit('core:frameworkDegraded', { framework = selectedName, errorCode = err.code }) end
    local Resources = NEXM_INTERNAL.Managers.Resources
    if Resources and Resources.NotifyComponentChanged then Resources.NotifyComponentChanged('framework', Health.UNAVAILABLE) end
end

local function recover()
    if not selectedAdapter or selectedName == 'standalone' then return end
    local valid, contractErr = Contract.Validate(selectedAdapter)
    if not valid then
        State.SetComponent('framework', Health.FAILED, { name = selectedName, error = contractErr })
        Logger.Infrastructure(contractErr, 'framework', 'nexm_core')
        return
    end
    local okAvailable, available = pcall(selectedAdapter.IsAvailable)
    if not okAvailable or not available then return end
    local callOk, initOk, initErr = pcall(selectedAdapter.Initialize)
    if not callOk or initOk ~= true then
        local err = Errors.Is(initErr) and initErr or Errors.Create(Codes.FRAMEWORK_INITIALIZATION_FAILED,
            'Framework recovery initialization failed', { framework = selectedName })
        State.SetComponent('framework', Health.FAILED, { name = selectedName, error = err })
        Logger.Infrastructure(err, 'framework', 'nexm_core')
        return
    end

    -- The adapter itself is initialized at this point. Mark the component healthy
    -- before cache reconstruction because Lifecycle.ReconstructPlayers() uses the
    -- same fail-closed Framework.RequireHealthy() gate as public player services.
    State.SetComponent('framework', Health.HEALTHY, componentDetails(selectedAdapter))
    local moneyCaps = selectedAdapter.metadata.capabilities.money or {}
    State.SetComponent('money', (moneyCaps.cash or moneyCaps.bank) and Health.HEALTHY or Health.UNAVAILABLE, { framework = selectedName, capabilities = copy(moneyCaps) })
    local Lifecycle = NEXM_INTERNAL.Modules.Lifecycle
    if Lifecycle then
        local attachOk, attachErr = Lifecycle.AttachAdapter(selectedAdapter)
        if not attachOk then
            State.SetComponent('framework', Health.FAILED, { name = selectedName, error = attachErr })
            Logger.Infrastructure(attachErr, 'framework', 'nexm_core')
            return
        end
        local rebuildOk, rebuildErr = Lifecycle.ReconstructPlayers()
        if not rebuildOk then
            State.SetComponent('framework', Health.FAILED, { name = selectedName, error = rebuildErr })
            Logger.Infrastructure(rebuildErr, 'framework', 'nexm_core')
            return
        end
    end
    if State.Get() == States.DEGRADED then State.Set(States.READY) end
    Logger.Info('Framework recovered using the same sticky adapter', componentDetails(selectedAdapter), 'nexm_core')
    TriggerEvent('nexm_core:server:frameworkRecovered', selectedName)
    local EventBus = NEXM_INTERNAL.Modules.EventBus
    if EventBus and EventBus.Emit then EventBus.Emit('core:frameworkRecovered', { framework = selectedName }) end
    local Resources = NEXM_INTERNAL.Managers.Resources
    if Resources and Resources.NotifyComponentChanged then Resources.NotifyComponentChanged('framework', Health.HEALTHY) end
end

function Framework.InstallResourceMonitoring()
    if monitorInstalled then return end
    monitorInstalled = true
    AddEventHandler('onResourceStop', function(resourceName)
        if not selectedAdapter or selectedName == 'standalone' then return end
        if resourceName == selectedAdapter.metadata.resource then degrade('resource_stop') end
    end)
    AddEventHandler('onResourceStart', function(resourceName)
        if not selectedAdapter or selectedName == 'standalone' then return end
        if resourceName ~= selectedAdapter.metadata.resource then return end
        CreateThread(function()
            if Wait then Wait(0) end
            recover()
        end)
    end)
end

NEXM_INTERNAL.Managers.Framework = Framework
