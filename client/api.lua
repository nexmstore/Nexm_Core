local State = NEXM_INTERNAL.Modules.ClientPlayerState
local Events = NEXM_INTERNAL.Modules.ClientEvents
local Validation = NEXM_INTERNAL.Modules.Validation
local Transport = NEXM_INTERNAL.Modules.Transport
local Constants = NEXM_INTERNAL.Modules.Constants
local Errors = NEXM_INTERNAL.Modules.Errors
local Callbacks = NEXM_INTERNAL.Modules.ClientCallbacks
local Notify = NEXM_INTERNAL.Modules.ClientNotify
local Locale = NEXM_INTERNAL.Modules.Locale
local Codes = Constants.ERROR_CODES

local facades = {}
local transportFacades = {}

local TRACE_CASES = {
    live_echo = 'echo',
    live_slow = 'timeout',
    callback_that_does_not_exist = 'unknown_callback',
    live_invalid_response = 'invalid_response'
}

local function debugTransportEnabled()
    return GetConvarInt and GetConvarInt('nexm_debug_transport', 0) == 1
end

local function traceCase(name)
    return TRACE_CASES[name]
end

local function transportErrorCode(envelope)
    if type(envelope) ~= 'table' or type(envelope.entries) ~= 'table' then return nil end
    local entry = envelope.entries[2]
    local value = type(entry) == 'table' and entry.value or nil
    return type(value) == 'table' and value.code or nil
end

local function emitTrace(trace)
    if not debugTransportEnabled() or type(trace) ~= 'table' then return end
    trace.buildId = Constants.BUILD_ID
    trace.producerResource = GetCurrentResourceName and GetCurrentResourceName() or 'nexm_core'
    print(('[NEXM TRANSPORT][%s] build=%s case=%s callback=%s returnCount=%s secondType=%s errorCode=%s transportTupleN=%s transportErrorCode=%s owner=%s'):format(
        tostring(trace.layer), tostring(trace.buildId), tostring(trace.case), tostring(trace.callbackName),
        tostring(trace.returnCount), tostring(trace.secondType), tostring(trace.errorCode),
        tostring(trace.transportTupleN), tostring(trace.transportErrorCode), tostring(trace.ownerResource)
    ))
    if TriggerEvent then TriggerEvent('nexm_core:diagnostic:transportTrace', trace) end
end
local function sanitizeOwner(value)
    return type(value) == 'string' and #value > 0 and #value <= 128
        and value:match('^[%w%._%-]+$') and value or nil
end
local function invokingOwner()
    local invoking = GetInvokingResource and sanitizeOwner(GetInvokingResource()) or nil
    local current = GetCurrentResourceName and sanitizeOwner(GetCurrentResourceName()) or 'nexm_core'
    -- Calls to methods on an exported Core facade are themselves Cfx function
    -- references. Resolve their actual invoking resource lazily; this avoids
    -- binding RPC routing to nexm_core when the initial export call has no
    -- usable invoking-resource context on a real client runtime.
    if invoking and invoking ~= current then return invoking end
    return nil
end
local function ownerError()
    return Errors.Create(Codes.RPC_UNAVAILABLE, 'Unable to determine requesting client resource for resource-bound operation')
end
local function callbackAwait(boundOwner, transportMode, name, payload, options)
    local owner = invokingOwner() or boundOwner
    if not owner then
        local err = ownerError()
        if transportMode then
            local envelope = Transport.Pack(nil, err)
            if traceCase(name) then
                emitTrace({
                    layer='B_TRANSPORT_PACK', case=traceCase(name), callbackName=name,
                    returnCount=1, firstType=type(envelope), secondType='nil',
                    errorCode=transportErrorCode(envelope), transportTupleN=envelope.n,
                    transportErrorCode=transportErrorCode(envelope), ownerResource=owner
                })
            end
            return envelope
        end
        return nil, err
    end

    if transportMode then
        local response = Callbacks.AwaitEnvelope(owner, name, payload, options)
        local envelope
        if response.ok == true then envelope = Transport.Pack(response.value, nil)
        else envelope = Transport.Pack(nil, response.error) end
        if traceCase(name) then
            emitTrace({
                layer='B_TRANSPORT_PACK', case=traceCase(name), callbackName=name,
                returnCount=1, firstType=type(envelope), secondType='nil',
                errorCode=transportErrorCode(envelope), transportTupleN=envelope.n,
                transportErrorCode=transportErrorCode(envelope), ownerResource=owner
            })
        end
        return envelope
    end

    local packed = table.pack(Callbacks.Await(owner, name, payload, options))
    if traceCase(name) then
        emitTrace({
            layer='B_DIRECT_NONTRANSPORT', case=traceCase(name), callbackName=name,
            returnCount=packed.n, firstType=type(packed[1]), secondType=type(packed[2]),
            errorCode=type(packed[2])=='table' and packed[2].code or nil, ownerResource=owner
        })
    end
    return table.unpack(packed,1,packed.n)
end
local function build(boundOwner)
    local function ownerForCall()
        return invokingOwner() or boundOwner
    end
    return {
        Player = {
            GetLocal = function() return State.Get() end,
            IsLoaded = function() return State.IsLoaded() end
        },
        Callback = {
            Await = function(name, payload, options)
                return callbackAwait(boundOwner, false, name, payload, options)
            end
        },
        Notify = {
            Send = function(message, notifyType, duration, options) return Notify.Send(message, notifyType, duration, options) end
        },
        Locale = {
            Register = function(locale, strings)
                local owner = ownerForCall(); if not owner then return false, ownerError() end
                return Locale.Register(locale, strings, owner)
            end,
            Get = function(key, vars)
                local owner = ownerForCall(); if not owner then return key end
                return Locale.Get(key, vars, owner)
            end,
            SetFallback = function(locale)
                local owner = ownerForCall(); if not owner then return false, ownerError() end
                return Locale.SetFallback(locale, owner)
            end
        },
        Events = {
            OnPlayerLoaded = function(cb)
                local owner = ownerForCall(); if not owner then return false, ownerError() end
                return Events.Subscribe('playerLoaded', cb, owner)
            end,
            OnPlayerUnloaded = function(cb)
                local owner = ownerForCall(); if not owner then return false, ownerError() end
                return Events.Subscribe('playerUnloaded', cb, owner)
            end,
            OnJobChanged = function(cb)
                local owner = ownerForCall(); if not owner then return false, ownerError() end
                return Events.Subscribe('jobChanged', cb, owner)
            end,
            OnDutyChanged = function(cb)
                local owner = ownerForCall(); if not owner then return false, ownerError() end
                return Events.Subscribe('dutyChanged', cb, owner)
            end
        },
        Validate = Validation,
        Version = { Get = function() return Constants.VERSION end }
    }
end
function GetCoreObject(transportMode)
    local owner = invokingOwner()
    local cacheKey = owner or '@deferred'
    if not facades[cacheKey] then facades[cacheKey] = build(owner) end
    if Transport and Transport.IsRequested(transportMode) then
        if not transportFacades[cacheKey] then
            local transportFacade = Transport.WrapFacade(facades[cacheKey])
            -- Callback.Await is the only public client method that yields across
            -- a real Cfx function-reference boundary. Keep its internal result
            -- as one envelope until this boundary, then let import.lua restore
            -- the public `result, err` tuple locally in the consumer resource.
            transportFacade.Callback.Await = function(name, payload, options)
                local envelope = callbackAwait(owner, true, name, payload, options)
                if traceCase(name) then
                    emitTrace({
                        layer='B_PUBLIC_CALLBACK', case=traceCase(name), callbackName=name,
                        returnCount=1, firstType=type(envelope), secondType='nil',
                        errorCode=transportErrorCode(envelope),
                        transportTupleN=type(envelope)=='table' and envelope.n or nil,
                        transportErrorCode=transportErrorCode(envelope),
                        ownerResource=invokingOwner() or owner
                    })
                end
                return envelope
            end
            transportFacades[cacheKey] = transportFacade
        end
        return transportFacades[cacheKey]
    end
    return facades[cacheKey]
end
exports('GetCoreObject', GetCoreObject)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    if Locale and Locale.CleanupOwner then Locale.CleanupOwner(resourceName) end
    facades[resourceName] = nil
    transportFacades[resourceName] = nil
end)
