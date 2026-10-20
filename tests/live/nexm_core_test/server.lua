local NEXM = exports['nexm_core']:GetCoreObject()

local ok, err = NEXM.Resources.Register({
    name = 'nexm_core_test',
    version = '0.1.0',
    requiresCore = '>=1.0.0-0',
    requirements = { framework = true }
})
if not ok then error(('nexm_core_test registration failed: %s'):format(err and err.code or 'unknown')) end

NEXM.Locale.Register('en', {
    live = { hello = 'Hello, {name}' }
})
NEXM.Locale.Register('lt', {
    live = { hello = 'Labas, {name}' }
})

NEXM.Permissions.Define('live_police', {
    mode = 'any',
    jobs = { police = { minimumGrade = 1, requireDuty = true } }
})

local echoCalls = 0
NEXM.Callback.Register('echo', function(source, payload, context)
    echoCalls = echoCalls + 1
    return { payload = payload, source = source, sessionCurrent = context:IsCurrentSession() }
end, { rateLimit = { limit = 20, window = 10 }, requireCharacter = true })

NEXM.Callback.Register('slow', function(source, payload, context)
    Wait(2000)
    return { done = true, sessionCurrent = context:IsCurrentSession() }
end, { requireCharacter = true })

NEXM.Services.Register('live_probe', {
    Ping = function() return 'pong' end,
    EchoCalls = function() return echoCalls end
}, { version = '0.1.0', apiVersion = 1, capabilities = { liveTest = true } })

NEXM.Events.On('test:event', function(payload)
    NEXM.Log.Info('Live EventBus event received', { payload = payload, component = 'live-test' })
end)

RegisterCommand('nexmtest:status', function(source)
    if source ~= 0 then return end
    local status = NEXM.GetStatus()
    print(('[NEXM TEST] Core=%s Version=%s'):format(status.state, status.version))
    for _, name in ipairs({ 'framework', 'money', 'inventory', 'notify', 'rpc', 'audit' }) do
        local component = NEXM.Components.Get(name)
        print(('[NEXM TEST] %s=%s provider=%s'):format(name, component and component.state or 'nil', component and tostring(component.provider) or '-'))
    end
end, false)

RegisterCommand('nexmtest:money', function(source, args)
    if source == 0 then print('[NEXM TEST] run this as a player command or adapt source in test environment'); return end
    local account = args[1] or 'cash'
    local amount, getErr = NEXM.Money.Get(source, account)
    print(('[NEXM TEST] Money.Get %s = %s err=%s'):format(account, tostring(amount), getErr and getErr.code or 'nil'))
end, false)

RegisterCommand('nexmtest:audit', function(source)
    local actor = source ~= 0 and source or nil
    local accepted, auditErr = NEXM.Audit.Log({ action = 'phase7_live_probe', actor = actor, severity = 'info', data = { marker = 'safe-test' } })
    print(('[NEXM TEST] Audit accepted=%s err=%s'):format(tostring(accepted), auditErr and auditErr.code or 'nil'))
end, false)

RegisterCommand('nexmtest:event', function(source)
    if source ~= 0 then return end
    NEXM.Events.Emit('test:event', { nested = { value = 1 } })
end, false)
