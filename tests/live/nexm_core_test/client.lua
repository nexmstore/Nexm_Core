local NEXM = exports['nexm_core']:GetCoreObject()

RegisterCommand('nexmtest:echo', function()
    local result, err = NEXM.Callback.Await('echo', { message = 'live' }, { timeout = 5000 })
    print(('[NEXM TEST] echo result=%s err=%s'):format(result and result.payload and result.payload.message or 'nil', err and err.code or 'nil'))
end, false)

RegisterCommand('nexmtest:timeout', function()
    local result, err = NEXM.Callback.Await('slow', {}, { timeout = 500 })
    print(('[NEXM TEST] timeout result=%s err=%s'):format(tostring(result), err and err.code or 'nil'))
end, false)

RegisterCommand('nexmtest:notify', function()
    for _, kind in ipairs({ 'info', 'success', 'warning', 'error' }) do
        local ok, err = NEXM.Notify.Send('NEXM live notify: ' .. kind, kind, 2500)
        print(('[NEXM TEST] notify %s ok=%s err=%s'):format(kind, tostring(ok), err and err.code or 'nil'))
    end
end, false)

RegisterCommand('nexmtest:locale', function()
    local text, err = NEXM.Locale.Get('live.hello', { name = 'Client' })
    print(('[NEXM TEST] locale=%s err=%s'):format(tostring(text), err and err.code or 'nil'))
end, false)
