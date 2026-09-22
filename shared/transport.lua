local Callable = NEXM_INTERNAL.Modules.Callable
local Constants = NEXM_INTERNAL.Modules.Constants

local Transport = {}
Transport.MARKER = '__nexm_transport_v2'
Transport.DIAGNOSTIC_BUILD_KEY = '__nexmBuildId'
Transport.DIAGNOSTIC_PROBE_KEY = '__nexmTransportProbe'

local function encodeValue(value, seen)
    if Callable and Callable.Is(value) then
        local target = value
        return function(...)
            return Transport.Pack(target(...))
        end
    end

    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return '<cycle>' end
    seen[value] = true

    local out = {}
    for key, item in pairs(value) do
        local safeKey = encodeValue(key, seen)
        local safeValue = encodeValue(item, seen)
        out[safeKey] = safeValue
    end
    seen[value] = nil
    return out
end

-- Pack every Lua return slot into a dense array entry. Do not represent a
-- leading/middle nil as a sparse numeric table: Cfx function references pass
-- values through msgpack and the public NEXM contracts depend on exact tuple
-- arity (`nil, err` in particular).
function Transport.Pack(...)
    local tuple = table.pack(...)
    local entries = {}
    for i = 1, tuple.n do
        if tuple[i] == nil then
            entries[i] = { isNil = true }
        else
            entries[i] = { value = encodeValue(tuple[i], {}) }
        end
    end
    return {
        __nexmTransport = Transport.MARKER,
        n = tuple.n,
        entries = entries
    }
end

local function probe(caseName)
    if caseName == 'hello' then
        return Transport.Pack('hello')
    end
    if caseName == 'false' then
        return Transport.Pack(false)
    end
    if caseName == 'error' then
        return Transport.Pack(nil, {
            code = 'TEST_ERROR',
            message = 'NEXM transport self-probe'
        })
    end
    if caseName == 'value_false' then
        return Transport.Pack('value', false)
    end
    if caseName == 'nil_nil' then
        return Transport.Pack(nil, nil)
    end
    if caseName == 'table_nil' then
        return Transport.Pack({ ok = true, kind = 'transport_probe' }, nil)
    end
    return Transport.Pack(nil, {
        code = 'INVALID_ARGUMENT',
        message = 'Unknown NEXM transport self-probe case'
    })
end

function Transport.WrapFacade(facade)
    local wrapped = encodeValue(facade, {})
    -- Internal transport diagnostics are present only on the transport facade.
    -- import.lua consumes and removes these keys before returning the public Core
    -- object to the dependent resource.
    wrapped[Transport.DIAGNOSTIC_BUILD_KEY] = Constants and Constants.BUILD_ID or nil
    wrapped[Transport.DIAGNOSTIC_PROBE_KEY] = probe
    return wrapped
end

function Transport.IsRequested(value)
    return value == Transport.MARKER
end

NEXM_INTERNAL.Modules.Transport = Transport
