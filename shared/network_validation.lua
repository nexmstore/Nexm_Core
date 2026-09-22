local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Validation = NEXM_INTERNAL.Modules.Validation
local Callable = NEXM_INTERNAL.Modules.Callable

local NetworkValidation = {}

local function limits(kind)
    local cfg = (Config and Config.Network and Config.Network[kind]) or {}
    return {
        maxDepth = cfg.maxDepth or 8,
        maxEntries = cfg.maxEntries or 128,
        maxStringLength = cfg.maxStringLength or 2048,
        maxTotalNodes = cfg.maxTotalNodes or 512,
        maxKeyLength = cfg.maxKeyLength or 128
    }
end

local function invalid(message, context)
    return nil, Errors.Create(Codes.INVALID_PAYLOAD, message or 'Invalid network payload', context or {})
end

local function validateAndCopy(value, kind)
    local lim = limits(kind or 'request')
    local seen, nodes = {}, 0

    local function walk(node, depth, path)
        nodes = nodes + 1
        if nodes > lim.maxTotalNodes then
            return invalid('Network payload exceeds total node limit', { path = path, maxTotalNodes = lim.maxTotalNodes })
        end
        if depth > lim.maxDepth then
            return invalid('Network payload exceeds maximum depth', { path = path, maxDepth = lim.maxDepth })
        end

        local t = type(node)
        if Callable and Callable.Is(node) then
            return invalid('Network payload contains an unsupported callable value', { path = path, actualType = 'function_reference' })
        end
        if t == 'nil' or t == 'boolean' then return node, nil end
        if t == 'number' then
            if not Validation.Finite(node) then return invalid('Network payload contains a non-finite number', { path = path }) end
            return node, nil
        end
        if t == 'string' then
            if #node > lim.maxStringLength then
                return invalid('Network payload string is too large', { path = path, length = #node, max = lim.maxStringLength })
            end
            return node, nil
        end
        if t ~= 'table' then
            return invalid('Network payload contains an unsupported value type', { path = path, actualType = t })
        end
        if seen[node] then return invalid('Network payload contains a cyclic table', { path = path }) end
        seen[node] = true

        local out, entries = {}, 0
        for key, item in pairs(node) do
            entries = entries + 1
            if entries > lim.maxEntries then
                seen[node] = nil
                return invalid('Network payload table exceeds entry limit', { path = path, maxEntries = lim.maxEntries })
            end

            local kt = type(key)
            local safeKey = key
            if kt == 'string' then
                if #key > lim.maxKeyLength or key:find('[%z\1-\31\127]') then
                    seen[node] = nil
                    return invalid('Network payload contains an invalid table key', { path = path })
                end
            elseif kt == 'number' then
                if not Validation.Finite(key) or key % 1 ~= 0 then
                    seen[node] = nil
                    return invalid('Network payload numeric keys must be finite integers', { path = path })
                end
            else
                seen[node] = nil
                return invalid('Network payload keys must be strings or integers', { path = path, actualType = kt })
            end

            local copied, err = walk(item, depth + 1, path .. '.' .. tostring(key))
            if err then seen[node] = nil; return nil, err end
            out[safeKey] = copied
        end
        seen[node] = nil
        return out, nil
    end

    return walk(value, 1, kind or 'payload')
end

function NetworkValidation.Request(value) return validateAndCopy(value, 'request') end
function NetworkValidation.Response(value)
    local copied, err = validateAndCopy(value, 'response')
    if err then
        return nil, Errors.Create(Codes.RPC_INVALID_RESPONSE, 'RPC response is not network-safe', {
            cause = err.code,
            detail = err.message
        })
    end
    return copied, nil
end

function NetworkValidation.CallbackName(name)
    local ok, err = Validation.String(name, {
        name = 'callback name', nonEmpty = true, min = 1,
        max = (Config and Config.Callback and Config.Callback.maxNameLength) or 64,
        pattern = '^[%a_][%w_]*$'
    })
    if not ok then return false, Errors.Create(Codes.INVALID_CALLBACK_NAME, 'Invalid RPC callback name') end
    return true, nil
end

function NetworkValidation.RouteOwner(owner)
    local ok = type(owner) == 'string' and #owner > 0 and #owner <= 128 and owner:match('^[%w%._%-]+$') ~= nil
    if not ok then return false, Errors.Create(Codes.INVALID_PAYLOAD, 'Invalid RPC routing owner') end
    return true, nil
end

function NetworkValidation.RequestId(requestId)
    local ok, err = Validation.String(requestId, {
        name = 'request id', nonEmpty = true, min = 1,
        max = (Config and Config.Callback and Config.Callback.maxRequestIdLength) or 64,
        pattern = '^[%w%._:%-]+$'
    })
    if not ok then return false, Errors.Create(Codes.INVALID_REQUEST_ID, 'Invalid RPC request id') end
    return true, nil
end

NEXM_INTERNAL.Modules.NetworkValidation = NetworkValidation
