local Contract = NEXM_INTERNAL.Modules.NotifyContract
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local Manager = {}
local adapters = NEXM_INTERNAL.Adapters.Notify
local selected = nil
local primary = nil

local function frameworkName()
    local configured = Config and Config.Framework or 'auto'
    if configured == 'qbox' then return 'qbox' end
    if configured == 'qbcore' then return 'qbcore' end
    if configured == 'esx' then return 'esx' end
    if GetResourceState and GetResourceState('qbx_core') == 'started' then return 'qbox' end
    if GetResourceState and GetResourceState('qb-core') == 'started' then return 'qbcore' end
    if GetResourceState and GetResourceState('es_extended') == 'started' then return 'esx' end
    return nil
end

local function expandPriority()
    local out, seen = {}, {}
    local function add(name)
        if name and not seen[name] then seen[name] = true; out[#out + 1] = name end
    end
    for _, name in ipairs((Config and Config.NotifyPriority) or {'nexm_notify','ox_lib','framework'}) do
        if name == 'framework' then add(frameworkName()) else add(name) end
    end
    add('nexm_notify'); add('ox_lib'); add(frameworkName()); add('custom')
    return out
end

local function validateBuiltins()
    for name, adapter in pairs(adapters) do
        local ok, err = Contract.ValidateAdapter(adapter)
        if not ok then return false, err end
    end
    if NEXM_CUSTOM_NOTIFY_ADAPTER then
        local ok, err = Contract.ValidateAdapter(NEXM_CUSTOM_NOTIFY_ADAPTER)
        if not ok then return false, err end
        adapters.custom = NEXM_CUSTOM_NOTIFY_ADAPTER
    end
    return true, nil
end

local function available(name)
    local adapter = name and adapters[name] or nil
    if not adapter then return false end
    local ok, result = pcall(adapter.IsAvailable)
    return ok and result == true
end

local function desiredPrimary()
    local configured = Config and Config.Notify or 'auto'
    if configured == 'none' then return nil, 'DISABLED' end
    if configured ~= 'auto' then return configured, nil end
    if primary then return primary, nil end
    for _, name in ipairs(expandPriority()) do if available(name) then return name, nil end end
    return nil, 'UNAVAILABLE'
end

function Manager.Refresh()
    local ok, err = validateBuiltins(); if not ok then selected = nil; return false, err end
    local desired, state = desiredPrimary()
    if state == 'DISABLED' then primary=nil; selected=nil; return false, Errors.Create(Codes.NOTIFY_DISABLED,'Notifications are disabled') end
    if desired and not primary then primary = desired end
    if desired and available(desired) then selected = desired; return true, desired end

    -- Manual or previously selected provider is unavailable. Fallback is only
    -- considered when explicitly enabled, and always follows deterministic priority.
    if Config and Config.NotifyFallback == true then
        for _, name in ipairs(expandPriority()) do
            if name ~= desired and available(name) then selected=name; return true,name end
        end
    end
    selected = nil
    return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE,'No usable notification provider is available')
end

function Manager.GetName() return selected end
function Manager.GetState()
    if Config and Config.Notify == 'none' then return 'DISABLED' end
    return selected and available(selected) and 'HEALTHY' or 'UNAVAILABLE'
end
function Manager.Send(message, notifyType, duration, options, forcedProvider)
    local payload, err = Contract.ValidatePayload(message, notifyType, duration, options)
    if not payload then return false, err end
    if Config and Config.Notify == 'none' then return false, Errors.Create(Codes.NOTIFY_DISABLED,'Notifications are disabled') end
    local provider = forcedProvider
    if provider and available(provider) then selected = provider else
        local ok; ok, provider = Manager.Refresh(); if not ok then return false, provider end
    end
    local adapter = adapters[provider]
    if not adapter then return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE,'Selected notification adapter is unavailable') end
    local ok, result, sendErr = pcall(adapter.Send, payload.message, payload.type, payload.duration, payload.options)
    if not ok then return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE,'Notification adapter threw during send') end
    if result ~= true then return false, sendErr or Errors.Create(Codes.NOTIFY_UNAVAILABLE,'Notification adapter failed') end
    return true,nil
end

AddEventHandler('onClientResourceStart', function() Manager.Refresh() end)
AddEventHandler('onClientResourceStop', function() Manager.Refresh() end)

NEXM_INTERNAL.Managers.ClientNotify = Manager
