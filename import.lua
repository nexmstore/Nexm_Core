-- NEXM Core consumer transport shim.
-- Load this from dependent resources before calling exports['nexm_core']:GetCoreObject().
--
-- Cfx function-reference calls do not safely preserve a Lua return tuple whose
-- first slot is nil. NEXM therefore requests a transport-safe facade from
-- nexm_core and decodes its single-value return envelopes locally in the
-- consumer resource. The public API remains ordinary Lua: `result, err`.
--
-- IMPORTANT: patch the existing Cfx `exports` table in place. Replacing the
-- global `exports` variable is not sufficient for all real resource/script
-- lookup paths. An in-place metatable hook preserves every existing reference
-- to the Cfx exports table while intercepting only nexm_core:GetCoreObject().

local rawExports = exports
local MARKER = '__nexm_transport_v2'
local INSTALL_KEY = '__nexm_transport_import_v2'
local BUILD_ID = 'mvp_rc1_matrix_13401539'
local BUILD_KEY = '__nexmBuildId'
local PROBE_KEY = '__nexmTransportProbe'
local DIAGNOSTICS_KEY = '__NEXM_IMPORT_DIAGNOSTICS'
local CALLBACK_RETURN_MARKER = '__nexm_callback_return_v1'
local TRACE_CASES = {
    live_echo = 'echo',
    live_slow = 'timeout',
    callback_that_does_not_exist = 'unknown_callback',
    live_invalid_response = 'invalid_response'
}

local function debugEnabled()
    return GetConvarInt and GetConvarInt('nexm_debug_transport', 0) == 1
end

local function emitTrace(trace)
    if not debugEnabled() or type(trace) ~= 'table' then return end
    trace.buildId = BUILD_ID
    trace.producerResource = GetCurrentResourceName and GetCurrentResourceName() or 'consumer'
    print(('[NEXM TRANSPORT][%s] build=%s consumer=%s callback=%s returnCount=%s secondType=%s errorCode=%s envelopeTupleN=%s envelopeErrorCode=%s'):format(
        tostring(trace.layer), tostring(trace.buildId), tostring(trace.producerResource),
        tostring(trace.callbackName), tostring(trace.returnCount), tostring(trace.secondType),
        tostring(trace.errorCode), tostring(trace.envelopeTupleN), tostring(trace.envelopeErrorCode)
    ))
    if TriggerEvent then
        TriggerEvent('nexm_core:diagnostic:transportTrace', trace)
    end
end

local function isCfxFunctionReference(value)
    return type(value) == 'table' and rawget(value, '__cfx_functionReference') ~= nil
end

local function isCallable(value)
    if type(value) == 'function' then return true end
    if not isCfxFunctionReference(value) then return false end
    local mt = getmetatable(value)
    return type(mt) == 'table' and type(mt.__call) == 'function'
end

local function callableKind(value)
    if isCfxFunctionReference(value) then return 'cfx_function_ref' end
    return type(value)
end

local wrapValue

local function transportError()
    return nil, { code = 'INTEGRATION_ERROR', message = 'Invalid NEXM transport envelope' }
end

local function unpackEnvelope(envelope)
    if type(envelope) ~= 'table' or envelope.__nexmTransport ~= MARKER then
        return wrapValue(envelope)
    end

    local n = envelope.n
    local entries = envelope.entries
    if type(n) ~= 'number' or n < 0 or n % 1 ~= 0 or n > 128 or type(entries) ~= 'table' then
        return transportError()
    end

    local out = { n = n }
    for i = 1, n do
        local entry = entries[i]
        if type(entry) ~= 'table' then return transportError() end
        if entry.isNil == true then
            -- Keep this slot absent while retaining exact tuple arity in out.n.
        elseif entry.isNil == nil and entry.value ~= nil then
            out[i] = wrapValue(entry.value)
        else
            return transportError()
        end
    end
    return table.unpack(out, 1, n)
end

local function envelopeErrorCode(envelope)
    if type(envelope) ~= 'table' or type(envelope.entries) ~= 'table' then return nil end
    local entry = envelope.entries[2]
    local value = type(entry) == 'table' and entry.value or nil
    return type(value) == 'table' and value.code or nil
end

local function envelopePresent(envelope)
    return type(envelope) == 'table' and envelope.__nexmTransport == MARKER
end

local function containsTransportMarker(value, seen, depth)
    if type(value) ~= 'table' then return false end
    depth = depth or 0
    if depth > 8 then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    if rawget(value, '__nexmTransport') ~= nil or rawget(value, BUILD_KEY) ~= nil or rawget(value, PROBE_KEY) ~= nil then
        return true
    end
    for key, item in pairs(value) do
        if containsTransportMarker(key, seen, depth + 1) or containsTransportMarker(item, seen, depth + 1) then
            return true
        end
    end
    return false
end

local function recordWrappedPath(registry, path)
    if type(registry) ~= 'table' or type(path) ~= 'string' or path == '' then return end
    registry[path] = true
end

local function packCallbackReturn(...)
    local tuple = table.pack(...)
    local entries = {}
    for i = 1, tuple.n do
        if tuple[i] == nil then
            entries[i] = { isNil = true }
        else
            entries[i] = { value = tuple[i] }
        end
    end
    return {
        __nexmCallbackReturn = CALLBACK_RETURN_MARKER,
        n = tuple.n,
        entries = entries
    }
end

local function prepareRemoteArgs(callPath, ...)
    local args = table.pack(...)
    -- Callback handlers execute back in the registering consumer resource.
    -- Wrap their logical return tuple into one non-nil Cfx-safe value so
    -- `nil, err` survives the function-reference boundary back to Core.
    if callPath == 'Callback.Register' and isCallable(args[2]) then
        local handler = args[2]
        args[2] = function(...)
            return packCallbackReturn(handler(...))
        end
    end
    return args
end

local function invokeWrapped(remote, callPath, observer, ...)
    local callArgs = prepareRemoteArgs(callPath, ...)
    local remotePacked = table.pack(remote(table.unpack(callArgs, 1, callArgs.n)))
    local envelope = remotePacked[1]
    if callPath == 'Callback.Await' then
        emitTrace({
            layer = 'C_REMOTE_BOUNDARY',
            case = TRACE_CASES[select(1, ...)],
            callbackName = select(1, ...),
            returnCount = remotePacked.n,
            firstType = type(remotePacked[1]),
            secondType = type(remotePacked[2]),
            errorCode = envelopeErrorCode(envelope),
            envelopeTupleN = type(envelope) == 'table' and envelope.n or nil,
            envelopeErrorCode = envelopeErrorCode(envelope)
        })
    end
    local publicPacked = table.pack(unpackEnvelope(envelope))
    if callPath == 'Callback.Await' then
        emitTrace({
            layer = 'C_IMPORT_FACADE',
            case = TRACE_CASES[select(1, ...)],
            callbackName = select(1, ...),
            returnCount = publicPacked.n,
            firstType = type(publicPacked[1]),
            secondType = type(publicPacked[2]),
            errorCode = type(publicPacked[2]) == 'table' and publicPacked[2].code or nil,
            envelopeTupleN = type(envelope) == 'table' and envelope.n or nil,
            envelopeErrorCode = envelopeErrorCode(envelope)
        })
    end
    if observer then observer(remotePacked, envelope, publicPacked) end
    return table.unpack(publicPacked, 1, publicPacked.n)
end

wrapValue = function(value, seen, path, registry)
    if isCallable(value) then
        local remote = value
        local callPath = path
        recordWrappedPath(registry, callPath)
        return function(...)
            return invokeWrapped(remote, callPath, nil, ...)
        end
    end

    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local out = {}
    seen[value] = out
    for key, item in pairs(value) do
        if key ~= BUILD_KEY and key ~= PROBE_KEY then
            local wrappedKey = wrapValue(key, seen, nil, registry)
            local childPath = path
            if type(key) == 'string' then
                childPath = path and (path .. '.' .. key) or key
            end
            out[wrappedKey] = wrapValue(item, seen, childPath, registry)
        end
    end
    return out
end

local function scalarOrNil(value)
    local t = type(value)
    if t == 'string' or t == 'number' or t == 'boolean' then return value end
    return nil
end

local function decodedSummary(publicPacked)
    local first, second = publicPacked[1], publicPacked[2]
    local secondValue = nil
    if type(second) == 'boolean' then secondValue = second end
    return {
        decodedReturnCount = publicPacked.n,
        decodedFirstType = type(first),
        decodedSecondType = type(second),
        decodedFirstValue = scalarOrNil(first),
        decodedSecondValue = secondValue,
        decodedErrorCode = type(second) == 'table' and second.code or nil,
        decodedFirstTableOk = type(first) == 'table' and first.ok == true or false,
        publicMarkerLeak = containsTransportMarker(first) or containsTransportMarker(second)
    }
end

-- Import self-probe: proves the remote probe emits a valid single transport
-- envelope and that the decoder can reconstruct the logical tuple. This is not
-- interchangeable with the real consumer generic-wrapper probe below.
local function selfProbeCase(probe, caseName)
    local remotePacked = table.pack(probe(caseName))
    local envelope = remotePacked[1]
    local publicPacked = table.pack(unpackEnvelope(envelope))
    local out = decodedSummary(publicPacked)
    out.case = caseName
    out.remoteLogicalReturnCount = type(envelope) == 'table' and envelope.n or nil
    out.transportEnvelopePresent = envelopePresent(envelope)
    out.transportEnvelopeCount = remotePacked.n
    return out
end

local function evaluateProbeResults(results)
    return
        results.hello and results.hello.transportEnvelopePresent == true and results.hello.transportEnvelopeCount == 1 and
            results.hello.decodedReturnCount == 1 and results.hello.decodedFirstValue == 'hello' and
        results.falseValue and results.falseValue.transportEnvelopePresent == true and results.falseValue.transportEnvelopeCount == 1 and
            results.falseValue.decodedReturnCount == 1 and results.falseValue.decodedFirstType == 'boolean' and results.falseValue.decodedFirstValue == false and
        results.error and results.error.transportEnvelopePresent == true and results.error.transportEnvelopeCount == 1 and
            results.error.decodedReturnCount == 2 and results.error.decodedFirstType == 'nil' and results.error.decodedSecondType == 'table' and results.error.decodedErrorCode == 'TEST_ERROR' and
        results.valueFalse and results.valueFalse.transportEnvelopePresent == true and results.valueFalse.transportEnvelopeCount == 1 and
            results.valueFalse.decodedReturnCount == 2 and results.valueFalse.decodedFirstValue == 'value' and results.valueFalse.decodedSecondType == 'boolean' and results.valueFalse.decodedSecondValue == false and
        results.tableNil and results.tableNil.transportEnvelopePresent == true and results.tableNil.transportEnvelopeCount == 1 and
            results.tableNil.decodedReturnCount == 2 and results.tableNil.decodedFirstType == 'table' and results.tableNil.decodedFirstTableOk == true and results.tableNil.decodedSecondType == 'nil' and
        results.hello.publicMarkerLeak ~= true and results.falseValue.publicMarkerLeak ~= true and results.error.publicMarkerLeak ~= true and
            results.valueFalse.publicMarkerLeak ~= true and results.tableNil.publicMarkerLeak ~= true
end

local function runSelfProbe(probe)
    if not isCallable(probe) then
        return false, { error = 'PROBE_NOT_CALLABLE' }
    end
    local results = {
        hello = selfProbeCase(probe, 'hello'),
        falseValue = selfProbeCase(probe, 'false'),
        error = selfProbeCase(probe, 'error'),
        valueFalse = selfProbeCase(probe, 'value_false'),
        tableNil = selfProbeCase(probe, 'table_nil')
    }
    return evaluateProbeResults(results), results
end

-- Real consumer generic probe: the remote probe is first wrapped by the exact
-- same local callable wrapper used for customer-facing facade methods, then
-- invoked from the consumer resource. The observer only records diagnostics; it
-- does not alter returned values.
local function realProbeCase(probe, caseName)
    local observed = {}
    local wrappedProbe = function(...)
        return invokeWrapped(probe, '__diagnostic.genericProbe', function(remotePacked, envelope, publicPacked)
            observed.remoteLogicalReturnCount = type(envelope) == 'table' and envelope.n or nil
            observed.transportEnvelopePresent = envelopePresent(envelope)
            observed.transportEnvelopeCount = remotePacked.n
            local decoded = decodedSummary(publicPacked)
            for key, value in pairs(decoded) do observed[key] = value end
        end, ...)
    end
    local publicPacked = table.pack(wrappedProbe(caseName))
    -- Use the actual consumer-visible tuple as the authority for decoded fields.
    local decoded = decodedSummary(publicPacked)
    for key, value in pairs(decoded) do observed[key] = value end
    observed.case = caseName
    return observed
end

local function runRealConsumerProbe(probe)
    if not isCallable(probe) then
        return false, { error = 'PROBE_NOT_CALLABLE' }
    end
    local results = {
        hello = realProbeCase(probe, 'hello'),
        falseValue = realProbeCase(probe, 'false'),
        error = realProbeCase(probe, 'error'),
        valueFalse = realProbeCase(probe, 'value_false'),
        tableNil = realProbeCase(probe, 'table_nil')
    }
    return evaluateProbeResults(results), results
end

local function runtimeSide()
    if type(IsDuplicityVersion) == 'function' then
        return IsDuplicityVersion() and 'server' or 'client'
    end
    return 'unknown'
end

local function metadataBuildId()
    if not GetResourceMetadata then return nil end
    local value = GetResourceMetadata('nexm_core', 'nexm_build', 0)
    return type(value) == 'string' and value or nil
end

local facadeStatusPrinted = false

local function publishDiagnostics(data, facadeReady)
    rawset(_G, DIAGNOSTICS_KEY, data)

    -- Release builds keep transport diagnostics available, but normal consumer
    -- startup is quiet. Enable nexm_debug_transport=1 only while diagnosing the
    -- transport/import path.
    local printStatus = debugEnabled()
    if printStatus then
        print(('[NEXM TRANSPORT][IMPORT] side=%s expectedBuild=%s metadataBuild=%s facadeBuild=%s importLoaded=%s facadeInitialized=%s proxyInstalled=%s callbackState=%s callbackRemote=%s callbackPublic=%s selfProbePassed=%s'):format(
            tostring(data.runtimeSide), tostring(data.expectedBuildId), tostring(data.metadataBuildId), tostring(data.facadeBuildId),
            tostring(data.importLoaded), tostring(data.facadeInitialized), tostring(data.proxyInstalled),
            tostring(data.callbackWrapperState), tostring(data.remoteCallbackKind), tostring(data.publicCallbackKind), tostring(data.probePassed)
        ))
        if facadeReady == true then facadeStatusPrinted = true end
    end

    if debugEnabled() and TriggerEvent then
        TriggerEvent('nexm_core:diagnostic:transportTrace', {
            layer = 'C_IMPORT_STATUS',
            buildId = BUILD_ID,
            producerResource = data.consumerResource,
            expectedBuildId = data.expectedBuildId,
            metadataBuildId = data.metadataBuildId,
            facadeBuildId = data.facadeBuildId,
            importLoaded = data.importLoaded,
            facadeInitialized = data.facadeInitialized,
            proxyInstalled = data.proxyInstalled,
            runtimeSide = data.runtimeSide,
            callbackWrapperState = data.callbackWrapperState,
            callbackLocallyProxied = data.callbackLocallyProxied,
            remoteCallbackKind = data.remoteCallbackKind,
            publicCallbackKind = data.publicCallbackKind,
            probePassed = data.probePassed
        })
    end
end

local function install()
    if type(rawExports) ~= 'table' then
        error('NEXM import requires the Cfx Lua exports table', 2)
    end

    local exportsMt = getmetatable(rawExports)
    if type(exportsMt) ~= 'table' or type(exportsMt.__index) ~= 'function' then
        error('NEXM import could not access the Cfx exports lookup', 2)
    end

    if exportsMt[INSTALL_KEY] == true then return end

    local rawIndex = exportsMt.__index
    local coreProxy

    exportsMt.__index = function(target, resource)
        if resource ~= 'nexm_core' then
            return rawIndex(target, resource)
        end

        if coreProxy then return coreProxy end

        local rawResource = rawIndex(target, resource)
        local proxy = {}
        setmetatable(proxy, {
            __index = function(_, exportName)
                if exportName ~= 'GetCoreObject' then
                    return rawResource[exportName]
                end

                return function(_, ...)
                    local remoteFacade = rawResource:GetCoreObject(MARKER, ...)
                    local facadeBuildId = type(remoteFacade) == 'table' and remoteFacade[BUILD_KEY] or nil
                    local probe = type(remoteFacade) == 'table' and remoteFacade[PROBE_KEY] or nil
                    local remoteCallback = type(remoteFacade) == 'table'
                        and type(remoteFacade.Callback) == 'table' and remoteFacade.Callback.Await or nil
                    local selfProbePassed, selfProbeResults = runSelfProbe(probe)
                    local wrappedMethods = {}
                    local publicFacade = wrapValue(remoteFacade, nil, nil, wrappedMethods)
                    local publicCallback = type(publicFacade) == 'table'
                        and type(publicFacade.Callback) == 'table' and publicFacade.Callback.Await or nil
                    local side = runtimeSide()
                    local callbackProxied = wrappedMethods['Callback.Await'] == true
                    local callbackState
                    if side == 'server' and not callbackProxied then
                        callbackState = 'NOT_APPLICABLE'
                    elseif callbackProxied then
                        callbackState = 'LOCAL_PROXY'
                    elseif isCfxFunctionReference(publicCallback) then
                        callbackState = 'RAW_REMOTE'
                    else
                        callbackState = 'UNPROVEN'
                    end
                    local metadataId = metadataBuildId()
                    publishDiagnostics({
                        expectedBuildId = BUILD_ID,
                        metadataBuildId = metadataId,
                        facadeBuildId = facadeBuildId,
                        buildIdentityMatch = metadataId == BUILD_ID and facadeBuildId == BUILD_ID,
                        consumerResource = GetCurrentResourceName and GetCurrentResourceName() or 'consumer',
                        runtimeSide = side,
                        importLoaded = true,
                        facadeInitialized = true,
                        proxyInstalled = true,
                        facadeProxy = true,
                        transportRequested = true,
                        remoteCallbackKind = callableKind(remoteCallback),
                        publicCallbackKind = callableKind(publicCallback),
                        callbackLocallyProxied = callbackProxied,
                        callbackWrapperState = callbackState,
                        proxiedNamespaces = { Callback = callbackProxied },
                        proxiedMethods = { ['Callback.Await'] = callbackProxied },
                        probePassed = selfProbePassed == true,
                        probes = selfProbeResults,
                        runRealConsumerProbe = function()
                            return runRealConsumerProbe(probe)
                        end
                    }, true)
                    return publicFacade
                end
            end,
            __newindex = function()
                error('cannot set values on export resource', 2)
            end
        })

        coreProxy = proxy
        return coreProxy
    end

    -- Mark the shared Cfx export object itself. Any script that captured the
    -- original `exports` table before this file loaded still observes the hook.
    exportsMt[INSTALL_KEY] = true

    -- This state differentiates "the client import file never executed" from
    -- "the import executed but no facade was constructed yet". It is replaced
    -- with the full facade diagnostics on the first canonical GetCoreObject().
    local side = runtimeSide()
    publishDiagnostics({
        expectedBuildId = BUILD_ID,
        metadataBuildId = metadataBuildId(),
        facadeBuildId = nil,
        buildIdentityMatch = false,
        consumerResource = GetCurrentResourceName and GetCurrentResourceName() or 'consumer',
        runtimeSide = side,
        importLoaded = true,
        facadeInitialized = false,
        proxyInstalled = true,
        facadeProxy = false,
        transportRequested = false,
        remoteCallbackKind = nil,
        publicCallbackKind = nil,
        callbackLocallyProxied = false,
        callbackWrapperState = 'PENDING',
        proxiedNamespaces = { Callback = false },
        proxiedMethods = { ['Callback.Await'] = false },
        probePassed = false,
        probes = nil
    }, false)
end

install()
