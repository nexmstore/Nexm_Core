local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local adapter = {
    metadata = {
        name='nexm_notify', resource='nexm_notify', version='1.0.3',
        capabilities={ advanced=true }, critical=false
    }
}

local function available()
    return GetResourceState and GetResourceState('nexm_notify') == 'started'
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function truncate(value, maxLength)
    if type(value) ~= 'string' then return value end
    if #value <= maxLength then return value end
    return value:sub(1, maxLength)
end

function adapter.IsAvailable()
    return available()
end

function adapter.Initialize()
    if available() then return true, nil end
    return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE, 'NEXM Notify is unavailable')
end

function adapter.Shutdown()
    return true, nil
end

function adapter.GetState()
    return available() and 'HEALTHY' or 'UNAVAILABLE'
end

function adapter.Send(message, notifyType, duration, options)
    if not available() then
        return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE, 'NEXM Notify is unavailable')
    end

    local typeMap = { info='info', success='success', warning='warning', error='error' }
    local payload = {
        type = typeMap[notifyType] or 'default',
        message = truncate(message, 300),
        duration = clamp(duration, 1000, 30000)
    }

    if options then
        if options.title ~= nil then payload.title = truncate(options.title, 80) end
        if options.id ~= nil then payload.id = options.id end
        -- options.position is intentionally not forwarded: NEXM Notify v1.0.3
        -- exposes global Config.Position, not per-notification positioning.
    end

    -- Resolve the export at dispatch time. Do not cache the function reference;
    -- `restart nexm_notify` must recover without restarting nexm_core.
    local ok, err = pcall(function()
        exports['nexm_notify']:Notify(payload)
    end)
    if not ok then
        return false, Errors.Create(Codes.NOTIFY_UNAVAILABLE, 'NEXM Notify dispatch failed', { detail=tostring(err) })
    end
    return true, nil
end

NEXM_INTERNAL.Adapters.Notify.nexm_notify = adapter
