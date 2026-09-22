local Integrations = NEXM_INTERNAL.Managers.Integrations
local Framework = NEXM_INTERNAL.Managers.Framework
local State = NEXM_INTERNAL.Modules.State
local Errors = NEXM_INTERNAL.Modules.Errors
local Logger = NEXM_INTERNAL.Modules.Logger
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Health = NEXM_INTERNAL.Modules.Constants.HEALTH

local Notify = {}
local initialized = false
local selected, primary = nil, nil
local providers = {
    nexm_notify = { resource='nexm_notify', capabilities={advanced=true} },
    ox_lib = { resource='ox_lib', capabilities={advanced=true} },
    esx = { resource='es_extended', capabilities={advanced=false} },
    qbcore = { resource='qb-core', capabilities={advanced=false} },
    qbox = { resource='qbx_core', capabilities={advanced=true} },
    custom = { resource='nexm_core', capabilities={advanced=false} }
}

local function frameworkProvider()
    local name = Framework and Framework.GetName and Framework.GetName() or nil
    if name == 'qbox' then return 'qbox' end
    if name == 'qbcore' then return 'qbcore' end
    if name == 'esx' then return 'esx' end
    return nil
end

local function frameworkCandidate(name)
    if not Framework or not Framework.DetectCandidates then return false end
    for _, candidate in ipairs(Framework.DetectCandidates()) do if candidate == name then return true end end
    return false
end

local function providerAvailable(name)
    if name == 'custom' then return Config and Config.NotifyCustomEnabled == true end
    if name == 'esx' then
        return frameworkCandidate('esx') and GetResourceState and GetResourceState('esx_notify') == 'started'
    end
    if name == 'qbcore' then return frameworkCandidate('qbcore') end
    if name == 'qbox' then return frameworkCandidate('qbox') end
    local p = providers[name]
    return p and GetResourceState and GetResourceState(p.resource) == 'started' or false
end

local function orderedCandidates()
    local out, seen = {}, {}
    local function add(name) if name and providers[name] and not seen[name] then seen[name]=true; out[#out+1]=name end end
    for _, name in ipairs((Config and Config.NotifyPriority) or {'nexm_notify','ox_lib','framework'}) do
        if name == 'framework' then add(frameworkProvider()) else add(name) end
    end
    add('nexm_notify'); add('ox_lib'); add(frameworkProvider()); add('custom')
    return out
end

local function registerProviders()
    if initialized then return true,nil end
    for name, p in pairs(providers) do
        local state = providerAvailable(name) and 'AVAILABLE' or 'UNAVAILABLE'
        local ok, err = Integrations.RegisterInternal({
            category='notify', name=name, version=GetResourceMetadata and (GetResourceMetadata(p.resource,'version') or '0.0.0') or '0.0.0',
            capabilities=p.capabilities, critical=false, state=state, adapter={clientSide=true}
        }, 'nexm_core')
        if not ok and not (err and err.code == Codes.REGISTRATION_EXISTS) then return false,err end
    end
    initialized = true
    return true,nil
end

local function updateProviderStates()
    for name in pairs(providers) do
        local state = providerAvailable(name) and 'AVAILABLE' or 'UNAVAILABLE'
        Integrations.SetStateInternal('notify',name,state,'nexm_core')
    end
end

local function desiredPrimary()
    local configured = Config and Config.Notify or 'auto'
    if configured == 'none' then return nil,'DISABLED' end
    if configured ~= 'auto' then return configured,nil end
    -- Auto selection is sticky once a primary provider has been chosen. A
    -- temporary fallback may be used only when explicitly enabled, but the
    -- primary remains the provider Core will resume when it recovers.
    if primary then return primary,nil end
    for _, name in ipairs(orderedCandidates()) do if providerAvailable(name) then return name,nil end end
    return nil,'UNAVAILABLE'
end

function Notify.Refresh(reason)
    local ok, err = registerProviders(); if not ok then return false,err end
    updateProviderStates()
    local desired, state = desiredPrimary()
    if state == 'DISABLED' then
        primary=nil; selected=nil; Integrations.ClearSelectedInternal('notify')
        State.SetComponent('notify',Health.DISABLED,{reason=reason})
        local Resources=NEXM_INTERNAL.Managers.Resources; if Resources and Resources.NotifyComponentChanged then Resources.NotifyComponentChanged('notify',Health.DISABLED) end
        return false, Errors.Create(Codes.NOTIFY_DISABLED,'Notifications are explicitly disabled')
    end
    if desired and not primary then primary=desired end
    if desired and providerAvailable(desired) then
        selected=desired; Integrations.SetSelectedInternal('notify',selected,{state='HEALTHY',fallback=false})
        Integrations.SetStateInternal('notify',selected,'HEALTHY','nexm_core')
        State.SetComponent('notify',Health.HEALTHY,{provider=selected,fallback=false})
        local Resources=NEXM_INTERNAL.Managers.Resources; if Resources and Resources.NotifyComponentChanged then Resources.NotifyComponentChanged('notify',Health.HEALTHY) end
        return true,selected
    end
    if Config and Config.NotifyFallback == true then
        for _, name in ipairs(orderedCandidates()) do
            if name ~= desired and providerAvailable(name) then
                selected=name; Integrations.SetSelectedInternal('notify',selected,{state='HEALTHY',fallback=true})
                Integrations.SetStateInternal('notify',selected,'HEALTHY','nexm_core')
                State.SetComponent('notify',Health.HEALTHY,{provider=selected,fallback=true,primary=desired or primary})
                local Resources=NEXM_INTERNAL.Managers.Resources; if Resources and Resources.NotifyComponentChanged then Resources.NotifyComponentChanged('notify',Health.HEALTHY) end
                return true,selected
            end
        end
    end
    selected=nil; Integrations.ClearSelectedInternal('notify')
    State.SetComponent('notify',Health.UNAVAILABLE,{primary=desired or primary,reason=reason})
    local Resources=NEXM_INTERNAL.Managers.Resources; if Resources and Resources.NotifyComponentChanged then Resources.NotifyComponentChanged('notify',Health.UNAVAILABLE) end
    return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE,'No notification provider is available')
end

function Notify.InitializeSelected()
    return Notify.Refresh('initialize')
end
function Notify.GetName() return selected end
function Notify.GetState() return State.GetComponent('notify') end
function Notify.IsHealthy() local c=State.GetComponent('notify'); return c and c.state==Health.HEALTHY or false end
function Notify.GetDiagnostics()
    local component = State.GetComponent('notify') or {}
    local details = component.details or {}
    local name = selected
    local p = name and providers[name] or nil
    local resource = p and p.resource or nil
    local resourceState = resource and GetResourceState and GetResourceState(resource) or nil
    return {
        provider = name,
        primary = primary,
        resource = resource,
        resourceState = resourceState,
        available = name and providerAvailable(name) or false,
        fallback = details.fallback == true
    }
end
function Notify.InstallResourceMonitoring()
    AddEventHandler('onResourceStart',function(resourceName)
        for _,p in pairs(providers) do if p.resource==resourceName or resourceName=='esx_notify' then Notify.Refresh('resource_start:'..resourceName); return end end
    end)
    AddEventHandler('onResourceStop',function(resourceName)
        for _,p in pairs(providers) do if p.resource==resourceName or resourceName=='esx_notify' then Notify.Refresh('resource_stop:'..resourceName); return end end
    end)
end

NEXM_INTERNAL.Managers.Notify = Notify
