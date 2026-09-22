-- Customer-editable custom notification adapter. It must satisfy the same
-- contract as built-in adapters. Enable with Config.Notify='custom' and
-- Config.NotifyCustomEnabled=true after implementing Send.
NEXM_CUSTOM_NOTIFY_ADAPTER = NEXM_CUSTOM_NOTIFY_ADAPTER or {
    metadata = {
        name = 'custom',
        resource = 'nexm_core',
        version = '1.0.0',
        capabilities = { advanced = false },
        critical = false,
        implemented = false
    }
}

function NEXM_CUSTOM_NOTIFY_ADAPTER.IsAvailable()
    return Config and Config.NotifyCustomEnabled == true and NEXM_CUSTOM_NOTIFY_ADAPTER.metadata.implemented == true
end
function NEXM_CUSTOM_NOTIFY_ADAPTER.Initialize() return true, nil end
function NEXM_CUSTOM_NOTIFY_ADAPTER.Shutdown() return true, nil end
function NEXM_CUSTOM_NOTIFY_ADAPTER.GetState()
    return NEXM_CUSTOM_NOTIFY_ADAPTER.IsAvailable() and 'HEALTHY' or 'UNAVAILABLE'
end
function NEXM_CUSTOM_NOTIFY_ADAPTER.Send(_message, _type, _duration, _options)
    return false, NEXM_INTERNAL.Modules.Errors.Create(
        NEXM_INTERNAL.Modules.Constants.ERROR_CODES.NOTIFY_UNAVAILABLE,
        'Custom notify adapter has not been implemented'
    )
end
