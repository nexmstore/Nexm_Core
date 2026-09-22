local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local NetworkValidation = NEXM_INTERNAL.Modules.NetworkValidation
local Constants = NEXM_INTERNAL.Modules.Constants
local Codes = Constants.ERROR_CODES

local ClientCallbacks = {}
local pending, counter = {}, 0

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

local function emitTrace(trace)
    if not debugTransportEnabled() or type(trace) ~= 'table' then return end
    trace.buildId = Constants.BUILD_ID
    trace.producerResource = GetCurrentResourceName and GetCurrentResourceName() or 'nexm_core'
    print(('[NEXM TRANSPORT][%s] build=%s case=%s callback=%s requestId=%s returnCount=%s secondType=%s errorCode=%s envelopeOk=%s responseOk=%s pendingFound=%s'):format(
        tostring(trace.layer), tostring(trace.buildId), tostring(trace.case), tostring(trace.callbackName),
        tostring(trace.requestId), tostring(trace.returnCount), tostring(trace.secondType),
        tostring(trace.errorCode), tostring(trace.envelopeOk), tostring(trace.responseOk), tostring(trace.pendingFound)
    ))
    if TriggerEvent then TriggerEvent('nexm_core:diagnostic:transportTrace', trace) end
end

local function envelopeErrorCode(envelope)
    return type(envelope) == 'table' and envelope.ok == false
        and type(envelope.error) == 'table' and envelope.error.code or nil
end

local function emitEnvelopeTrace(layer, name, id, envelope, meta)
    local caseName = traceCase(name)
    if not caseName then return end
    meta = meta or {}
    emitTrace({
        layer = layer,
        case = caseName,
        callbackName = name,
        requestId = id,
        returnCount = 1,
        firstType = type(envelope),
        secondType = 'nil',
        errorCode = envelopeErrorCode(envelope),
        envelopeOk = type(envelope) == 'table' and envelope.ok or nil,
        responseOk = meta.responseOk,
        pendingFound = meta.pendingFound
    })
end

local function now()
    if GetGameTimer then return tostring(GetGameTimer()) end
    return tostring(math.floor((os.clock and os.clock() or 0) * 1000))
end
local function requestId(_owner)
    counter = counter + 1
    if counter > 1000000000 then counter = 1 end
    return ('n:%s:%d'):format(now(), counter)
end
local function timeoutMs(options)
    local explicit = options and options.timeout
    local value = explicit or Config.Callback.Timeout
    local ok = type(value) == 'number' and value == value and value % 1 == 0
        and value >= Config.Callback.MinTimeout and value <= Config.Callback.MaxTimeout
    if not ok then return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'RPC timeout is outside configured safe limits') end
    return value, nil
end

local function successEnvelope(value)
    return { ok = true, value = value }
end

local function errorEnvelope(err)
    return { ok = false, error = err }
end

local function returnEnvelope(name, id, envelope)
    emitEnvelopeTrace('A_INTERNAL_CALLBACK', name, id, envelope)
    return envelope
end

-- Internal single-value contract. This is deliberately separate from the
-- public `result, err` contract: FiveM/Citizen promises resolve one value and
-- Cfx function-reference calls may yield while Await is pending. Keeping one
-- envelope until the resource boundary prevents error-path secondary returns
-- from being lost while preserving the public API at the facade/import layer.
function ClientCallbacks.AwaitEnvelope(ownerResource, name, payload, options)
    local nameOk, nameErr = NetworkValidation.CallbackName(name)
    if not nameOk then return returnEnvelope(name, nil, errorEnvelope(nameErr)) end

    local safePayload, payloadErr = NetworkValidation.Request(payload)
    if payloadErr then return returnEnvelope(name, nil, errorEnvelope(payloadErr)) end

    local id = requestId(ownerResource)
    if pending[id] then
        return returnEnvelope(name, id, errorEnvelope(Errors.Create(Codes.RPC_DUPLICATE_REQUEST, 'Duplicate client request id')))
    end

    local promiseObj = promise and promise.new and promise.new() or nil
    if not promiseObj or not Citizen or not Citizen.Await then
        return returnEnvelope(name, id, errorEnvelope(Errors.Create(Codes.RPC_UNAVAILABLE, 'RPC Await requires FiveM promise/Citizen.Await runtime')))
    end

    pending[id] = { ownerResource = ownerResource, name = name, promise = promiseObj, completed = false }
    local timeout, timeoutErr = timeoutMs(options)
    if not timeout then
        pending[id] = nil
        return returnEnvelope(name, id, errorEnvelope(timeoutErr))
    end

    SetTimeout(timeout, function()
        local item = pending[id]
        if not item or item.completed then return end
        item.completed = true
        pending[id] = nil
        local timeoutEnvelope = errorEnvelope({ code = Codes.RPC_TIMEOUT, message = 'RPC request timed out' })
        emitEnvelopeTrace('A_PROMISE_RESOLVE', name, id, timeoutEnvelope, { pendingFound = true })
        item.promise:resolve(timeoutEnvelope)
    end)

    TriggerServerEvent('nexm_core:rpc:request', id, ownerResource, name, safePayload)
    local response = Citizen.Await(promiseObj)
    emitEnvelopeTrace('A_CITIZEN_AWAIT', name, id, response)
    if type(response) ~= 'table' or type(response.ok) ~= 'boolean' then
        return returnEnvelope(name, id, errorEnvelope(Errors.Create(Codes.RPC_UNAVAILABLE, 'RPC request failed')))
    end
    if response.ok == true then return returnEnvelope(name, id, successEnvelope(response.value)) end
    if type(response.error) ~= 'table' or type(response.error.code) ~= 'string' then
        return returnEnvelope(name, id, errorEnvelope(Errors.Create(Codes.RPC_UNAVAILABLE, 'RPC request failed')))
    end
    return returnEnvelope(name, id, errorEnvelope(response.error))
end

function ClientCallbacks.Await(ownerResource, name, payload, options)
    local response = ClientCallbacks.AwaitEnvelope(ownerResource, name, payload, options)
    local packed
    if response.ok == true then packed = table.pack(response.value, nil)
    else packed = table.pack(nil, response.error) end
    if traceCase(name) then
        emitTrace({
            layer = 'A_DIRECT_TUPLE',
            case = traceCase(name),
            callbackName = name,
            returnCount = packed.n,
            firstType = type(packed[1]),
            secondType = type(packed[2]),
            errorCode = type(packed[2]) == 'table' and packed[2].code or nil
        })
    end
    return table.unpack(packed, 1, packed.n)
end

RegisterNetEvent('nexm_core:rpc:response', function(id, ok, value)
    local item = pending[id]
    if not item or item.completed then return end
    if traceCase(item.name) then
        emitTrace({
            layer = 'A_RESPONSE_EVENT',
            case = traceCase(item.name),
            callbackName = item.name,
            requestId = id,
            returnCount = 1,
            firstType = type(value),
            secondType = 'nil',
            errorCode = (not ok and type(value) == 'table') and value.code or nil,
            responseOk = ok,
            pendingFound = true
        })
    end
    item.completed = true; pending[id] = nil
    item.promise:resolve(ok and successEnvelope(value) or errorEnvelope(value))
end)

function ClientCallbacks.CleanupOwner(ownerResource)
    local removed = 0
    for id, item in pairs(pending) do
        if item.ownerResource == ownerResource then
            pending[id] = nil; item.completed = true; removed = removed + 1
            item.promise:resolve(errorEnvelope({ code = Codes.RPC_CALLBACK_UNAVAILABLE, message = 'Requesting resource stopped' }))
        end
    end
    return removed
end
function ClientCallbacks.CountPending() local n=0; for _ in pairs(pending) do n=n+1 end; return n end

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then ClientCallbacks.CleanupOwner(resourceName) end
end)

NEXM_INTERNAL.Modules.ClientCallbacks = ClientCallbacks
