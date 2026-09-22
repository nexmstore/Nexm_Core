local Manager = NEXM_INTERNAL.Managers.ClientNotify

RegisterNetEvent('nexm_core:client:notify', function(message, notifyType, duration, options, provider)
    local ok, err = Manager.Send(message, notifyType, duration, options, provider)
    if not ok and Config and Config.Debug then
        print(('[NEXM][CLIENT][WARN] Notification delivery failed: %s'):format(err and err.code or 'UNKNOWN'))
    end
end)

NEXM_INTERNAL.Modules.ClientNotify = {
    Send = function(message, notifyType, duration, options)
        return Manager.Send(message, notifyType, duration, options)
    end
}
