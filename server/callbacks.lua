local Validation = NEXM_INTERNAL.Modules.Validation
local NetworkValidation = NEXM_INTERNAL.Modules.NetworkValidation
local Errors = NEXM_INTERNAL.Modules.Errors
local Logger = NEXM_INTERNAL.Modules.Logger
local Ownership = NEXM_INTERNAL.Modules.Ownership
local Player = NEXM_INTERNAL.Modules.Player
local PlayerCache = NEXM_INTERNAL.Modules.PlayerCache
local Permissions = NEXM_INTERNAL.Modules.Permissions
local RateLimit = NEXM_INTERNAL.Modules.RateLimit
local RegistryBase = NEXM_INTERNAL.Modules.RegistryBase
local Constants = NEXM_INTERNAL.Modules.Constants
local Codes = Constants.ERROR_CODES
local Callable = NEXM_INTERNAL.Modules.Callable

local Callbacks = {}
local registry, generations, active = {}, {}, {}
local CALLBACK_RETURN_MARKER = '__nexm_callback_return_v1'

local function decodeConsumerCallbackReturn(value)
    if type(value) ~= 'table' or rawget(value, '__nexmCallbackReturn') ~= CALLBACK_RETURN_MARKER then
        return false, nil, nil
    end

    local n, entries = value.n, value.entries
    if type(n) ~= 'number' or n < 0 or n % 1 ~= 0 or n > 2 or type(entries) ~= 'table' then
        return nil, nil, Errors.Create(Codes.RPC_HANDLER_ERROR, 'Invalid callback return transport envelope')
    end

    local tuple = { n = n }
    for i = 1, n do
        local entry = entries[i]
        if type(entry) ~= 'table' then
            return nil, nil, Errors.Create(Codes.RPC_HANDLER_ERROR, 'Invalid callback return transport entry')
        end
        if entry.isNil == true then
            -- Preserve logical nil through tuple.n.
        elseif entry.isNil == nil and entry.value ~= nil then
            tuple[i] = entry.value
        else
            return nil, nil, Errors.Create(Codes.RPC_HANDLER_ERROR, 'Invalid callback return transport value')
        end
    end

    return true, tuple[1], tuple[2]
end

local TRACE_CASES = {
    callback_that_does_not_exist = 'unknown_callback',
    live_invalid_response = 'invalid_response'
}
local function debugTransportEnabled()
    return GetConvarInt and GetConvarInt('nexm_debug_transport', 0) == 1
end
local function emitServerTrace(source, requestId, name, errorCode, callbackFound, handlerEntered)
    local caseName = TRACE_CASES[name]
    if not caseName or not debugTransportEnabled() then return end
    local trace = {
        buildId = Constants.BUILD_ID,
        layer = 'SERVER_BEFORE_RESPONSE',
        case = caseName,
        callbackName = name,
        requestId = requestId,
        playerSource = source,
        responseOk = false,
        errorCode = errorCode,
        callbackFound = callbackFound,
        handlerEntered = handlerEntered,
        producerResource = GetCurrentResourceName and GetCurrentResourceName() or 'nexm_core'
    }
    print(('[NEXM TRANSPORT][SERVER_BEFORE_RESPONSE] build=%s case=%s requestId=%s ok=false errorCode=%s callbackFound=%s handlerEntered=%s'):format(
        tostring(trace.buildId), tostring(caseName), tostring(requestId), tostring(errorCode),
        tostring(callbackFound), tostring(handlerEntered)
    ))
    if TriggerEvent then TriggerEvent('nexm_core:diagnostic:transportTraceServer', trace) end
end

local function key(owner, name) return owner .. ':' .. name end
local function sanitizeError(err)
    if not Errors.Is(err) then return { code = Codes.RPC_HANDLER_ERROR, message = 'RPC handler failed' } end
    local messages = {
        [Codes.PERMISSION_DENIED] = 'Permission denied', [Codes.PERMISSION_NOT_DEFINED] = 'Permission denied',
        [Codes.RATE_LIMITED] = 'Rate limit exceeded', [Codes.STALE_CHARACTER_SESSION] = 'Character session changed',
        [Codes.PLAYER_NOT_FOUND] = 'Character is not loaded', [Codes.RPC_CALLBACK_NOT_FOUND] = 'Callback unavailable',
        [Codes.RPC_CALLBACK_UNAVAILABLE] = 'Callback unavailable', [Codes.INVALID_PAYLOAD] = 'Invalid request payload',
        [Codes.RPC_INVALID_RESPONSE] = 'Invalid callback response'
    }
    return { code = err.code, message = messages[err.code] or err.message or 'Request failed' }
end

local function send(source, requestId, success, value)
    if TriggerClientEvent then TriggerClientEvent('nexm_core:rpc:response', source, requestId, success, value) end
end
local function sendError(source, requestId, err) send(source, requestId, false, sanitizeError(err)) end

local function validateRateLimit(value)
    if value == nil then return true, nil, nil end
    if type(value) ~= 'table' then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Callback rateLimit must be a table') end
    local limit = value.limit or (Config.Callback.DefaultRateLimit and Config.Callback.DefaultRateLimit.limit) or 20
    local window = value.window or (Config.Callback.DefaultRateLimit and Config.Callback.DefaultRateLimit.window) or 10
    local ok, err = Validation.Integer(limit, { name = 'callback rate limit', min = 1, max = 100000 }); if not ok then return false, err end
    ok, err = Validation.Number(window, { name = 'callback rate window', min = 0.05, max = 3600 }); if not ok then return false, err end
    return true, nil, { limit = limit, window = window }
end

function Callbacks.Register(name, handler, options, ownerResource)
    local owner = ownerResource or Ownership.Resolve()
    local ok, err = NetworkValidation.CallbackName(name); if not ok then return false, err end
    if not Callable.Is(handler) then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Callback handler must be callable') end
    options = options or {}
    if type(options) ~= 'table' then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Callback options must be a table') end
    local k = key(owner, name)
    if registry[k] then return false, Errors.Create(Codes.REGISTRATION_EXISTS, 'Callback already registered', { ownerResource = owner, name = name }) end
    local rateOk, rateErr, rate = validateRateLimit(options.rateLimit); if not rateOk then return false, rateErr end
    if options.permission ~= nil then
        local pOk, pErr = Ownership.ValidateLocalName(options.permission); if not pOk then return false, pErr end
    end
    if options.requireCharacter ~= nil and type(options.requireCharacter) ~= 'boolean' then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'requireCharacter must be boolean') end
    if options.validate ~= nil and not Callable.Is(options.validate) then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Callback validator must be callable') end
    generations[k] = (generations[k] or 0) + 1
    registry[k] = {
        ownerResource = owner, name = name, handler = handler, registeredAt = os.time(), generation = generations[k],
        options = { rateLimit = rate or Config.Callback.DefaultRateLimit, permission = options.permission, requireCharacter = options.requireCharacter == true, validate = options.validate }
    }
    return true, nil
end

function Callbacks.CleanupOwner(ownerResource)
    local prefix, removed = ownerResource .. ':', 0
    for k, record in pairs(registry) do
        if record.ownerResource == ownerResource then registry[k] = nil; generations[k] = (generations[k] or 0) + 1; removed = removed + 1 end
    end
    return removed
end

local function setActive(source, requestId)
    active[source] = active[source] or {}
    if active[source][requestId] then return false end
    active[source][requestId] = true; return true
end
local function clearActive(source, requestId)
    if not active[source] then return end
    active[source][requestId] = nil
    if next(active[source]) == nil then active[source] = nil end
end
function Callbacks.CleanupSource(source) active[source] = nil end
function Callbacks.CountActive() local n=0; for _,map in pairs(active) do for _ in pairs(map) do n=n+1 end end; return n end
function Callbacks.CountRegistered() local n=0; for _ in pairs(registry) do n=n+1 end; return n end

local function markerFor(source)
    local snapshot = PlayerCache.Get(source)
    return {
        source = source,
        characterSessionId = PlayerCache.GetSession(source),
        characterIdentifier = snapshot and snapshot.identifier or nil
    }
end
local function validateMarker(marker)
    local current = PlayerCache.GetSession(marker.source)
    if current ~= marker.characterSessionId then
        return false, Errors.Create(Codes.STALE_CHARACTER_SESSION, 'Character session changed while RPC request was executing')
    end
    return true, nil
end
local function makeContext(source, ownerResource, marker)
    local context = {
        source = source,
        ownerResource = ownerResource,
        characterIdentifier = marker.characterIdentifier,
        characterSessionId = marker.characterSessionId
    }
    context.IsCurrentSession = function() return validateMarker(marker) end
    return RegistryBase.Copy(context)
end

function Callbacks.HandleRequest(source, requestId, routeOwner, name, payload)
    local sourceOk, sourceErr = Validation.Source(source); if not sourceOk then return false, sourceErr end
    local globalOk, globalErr = RateLimit.CheckInternal(source, '@rpc-global', {
        limit = Config.Security.RPCGlobalLimit.limit, window = Config.Security.RPCGlobalLimit.window, sessionScoped = false
    })
    if not globalOk then sendError(source, requestId, globalErr); return false, globalErr end

    local idOk, idErr = NetworkValidation.RequestId(requestId); if not idOk then sendError(source, tostring(requestId or ''), idErr); return false, idErr end
    local ownerOk, ownerErr = NetworkValidation.RouteOwner(routeOwner); if not ownerOk then sendError(source, requestId, ownerErr); return false, ownerErr end
    local nameOk, nameErr = NetworkValidation.CallbackName(name); if not nameOk then sendError(source, requestId, nameErr); return false, nameErr end
    if not setActive(source, requestId) then
        local err = Errors.Create(Codes.RPC_DUPLICATE_REQUEST, 'Duplicate active RPC request id')
        sendError(source, requestId, err); return false, err
    end

    local function finish(success, value) clearActive(source, requestId); send(source, requestId, success, value) end
    local record = registry[key(routeOwner, name)]
    if not record then
        local err = Errors.Create(Codes.RPC_CALLBACK_NOT_FOUND, 'RPC callback is not registered')
        emitServerTrace(source, requestId, name, err.code, false, false)
        clearActive(source, requestId); sendError(source, requestId, err); return false, err
    end
    local generation = record.generation
    local endpointOk, endpointErr = RateLimit.CheckInternal(source, '@rpc:' .. key(routeOwner, name), record.options.rateLimit or Config.Callback.DefaultRateLimit)
    if not endpointOk then clearActive(source, requestId); sendError(source, requestId, endpointErr); return false, endpointErr end

    local safePayload, payloadErr = NetworkValidation.Request(payload)
    if payloadErr then clearActive(source, requestId); sendError(source, requestId, payloadErr); return false, payloadErr end

    local capture = markerFor(source)
    if record.options.requireCharacter and not capture.characterSessionId then
        local err = Errors.Create(Codes.PLAYER_NOT_FOUND, 'Character is not loaded')
        clearActive(source, requestId); sendError(source, requestId, err); return false, err
    end

    if record.options.permission then
        local allowed, permissionErr = Permissions.Has(source, record.options.permission, record.ownerResource)
        if permissionErr then clearActive(source, requestId); sendError(source, requestId, permissionErr); return false, permissionErr end
        if not allowed then
            local err = Errors.Create(Codes.PERMISSION_DENIED, 'Permission denied')
            clearActive(source, requestId); sendError(source, requestId, err); return false, err
        end
    end

    if record.options.validate then
        local ok, result, validationErr = pcall(record.options.validate, safePayload)
        if not ok or result ~= true then
            local err = Errors.Is(validationErr) and validationErr or Errors.Create(Codes.INVALID_PAYLOAD, 'Callback-specific payload validation failed')
            if not ok and Config.Debug then Logger.Debug('Callback validator raw error', { ownerResource = record.ownerResource, callback = name, rawError = tostring(result) }, record.ownerResource) end
            clearActive(source, requestId); sendError(source, requestId, err); return false, err
        end
    end

    local context = makeContext(source, record.ownerResource, capture)
    local callOk, result, handlerErr = pcall(record.handler, source, safePayload, context)
    if callOk then
        local transported, transportedResult, transportedErr = decodeConsumerCallbackReturn(result)
        if transported == nil then
            clearActive(source, requestId); sendError(source, requestId, transportedErr); return false, transportedErr
        elseif transported == true then
            result, handlerErr = transportedResult, transportedErr
        end
    end
    if not callOk then
        local err = Errors.Create(Codes.RPC_HANDLER_ERROR, 'RPC handler execution failed', { ownerResource = record.ownerResource, callback = name })
        Logger.Infrastructure(err, 'rpc:' .. key(record.ownerResource, name), record.ownerResource)
        if Config.Debug then Logger.Debug('RPC handler raw error', { rawError = tostring(result) }, record.ownerResource) end
        clearActive(source, requestId); sendError(source, requestId, err); return false, err
    end
    if Errors.Is(handlerErr) then clearActive(source, requestId); sendError(source, requestId, handlerErr); return false, handlerErr end

    local current = registry[key(record.ownerResource, name)]
    if not current or current.generation ~= generation then
        local err = Errors.Create(Codes.RPC_CALLBACK_UNAVAILABLE, 'Callback owner changed while request was executing')
        clearActive(source, requestId); sendError(source, requestId, err); return false, err
    end
    local sessionOk, sessionErr = validateMarker(capture)
    if not sessionOk then clearActive(source, requestId); sendError(source, requestId, sessionErr); return false, sessionErr end

    local safeResponse, responseErr = NetworkValidation.Response(result)
    if responseErr then
        Logger.Infrastructure(responseErr, 'rpc:response:' .. key(record.ownerResource, name), record.ownerResource)
        emitServerTrace(source, requestId, name, responseErr.code, true, true)
        clearActive(source, requestId); sendError(source, requestId, responseErr); return false, responseErr
    end
    finish(true, safeResponse)
    return true, nil
end

RegisterNetEvent('nexm_core:rpc:request', function(requestId, routeOwner, name, payload)
    Callbacks.HandleRequest(source, requestId, routeOwner, name, payload)
end)
AddEventHandler('playerDropped', function() Callbacks.CleanupSource(tonumber(source)) end)

NEXM_INTERNAL.Modules.Callbacks = Callbacks
