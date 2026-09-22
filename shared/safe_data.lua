local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local SafeData = {}

local function defaultLimits(options)
    options = options or {}
    return {
        maxDepth = options.maxDepth or 8,
        maxEntries = options.maxEntries or 256,
        maxTotalNodes = options.maxTotalNodes or 768,
        maxStringLength = options.maxStringLength or 4096,
        maxKeyLength = options.maxKeyLength or 128
    }
end

function SafeData.Copy(value, options)
    local lim = defaultLimits(options)
    local seen, nodes = {}, 0
    local errorCode = options and options.errorCode or Codes.INVALID_ARGUMENT
    local field = options and options.field or 'data'

    local function fail(message, context)
        context = context or {}
        context.field = field
        return nil, Errors.Create(errorCode, message, context)
    end

    local function walk(node, depth, path)
        nodes = nodes + 1
        if nodes > lim.maxTotalNodes then
            return fail('Data exceeds total node limit', { path = path, maxTotalNodes = lim.maxTotalNodes })
        end
        if depth > lim.maxDepth then
            return fail('Data exceeds maximum depth', { path = path, maxDepth = lim.maxDepth })
        end

        local t = type(node)
        if t == 'nil' or t == 'boolean' then return node, nil end
        if t == 'number' then
            if not Validation.Finite(node) then return fail('Data contains a non-finite number', { path = path }) end
            return node, nil
        end
        if t == 'string' then
            if #node > lim.maxStringLength then
                return fail('Data string exceeds limit', { path = path, length = #node, max = lim.maxStringLength })
            end
            return node, nil
        end
        if t ~= 'table' then
            return fail('Data contains unsupported value type', { path = path, actualType = t })
        end
        if seen[node] then return fail('Data contains a cyclic table', { path = path }) end
        seen[node] = true

        local out, count = {}, 0
        for key, item in pairs(node) do
            count = count + 1
            if count > lim.maxEntries then
                seen[node] = nil
                return fail('Data table exceeds entry limit', { path = path, maxEntries = lim.maxEntries })
            end
            local kt = type(key)
            if kt == 'string' then
                if #key > lim.maxKeyLength or key:find('[%z\1-\31\127]') then
                    seen[node] = nil
                    return fail('Data contains an invalid string key', { path = path })
                end
            elseif kt == 'number' then
                if not Validation.Finite(key) or key % 1 ~= 0 then
                    seen[node] = nil
                    return fail('Data numeric keys must be finite integers', { path = path })
                end
            else
                seen[node] = nil
                return fail('Data keys must be strings or integers', { path = path, actualType = kt })
            end
            local copied, err = walk(item, depth + 1, path .. '.' .. tostring(key))
            if err then seen[node] = nil; return nil, err end
            out[key] = copied
        end
        seen[node] = nil
        return out, nil
    end

    return walk(value, 1, field)
end

-- Logging must never throw. Unsupported or excessively complex values are reduced
-- to bounded diagnostic strings instead of propagating serialization errors.
function SafeData.ForLog(value, options)
    options = options or {}
    local lim = defaultLimits(options)
    local seen, nodes = {}, 0

    local function walk(node, depth)
        nodes = nodes + 1
        if nodes > lim.maxTotalNodes then return '<node-limit>' end
        if depth > lim.maxDepth then return '<depth-limit>' end
        local t = type(node)
        if t == 'nil' or t == 'boolean' then return node end
        if t == 'number' then return Validation.Finite(node) and node or '<non-finite>' end
        if t == 'string' then
            return #node <= lim.maxStringLength and node or (node:sub(1, lim.maxStringLength) .. '...')
        end
        if t ~= 'table' then return '<' .. t .. '>' end
        if seen[node] then return '<cycle>' end
        seen[node] = true
        local out, count = {}, 0
        for key, item in pairs(node) do
            count = count + 1
            if count > lim.maxEntries then out['<truncated>'] = true; break end
            local safeKey = (type(key) == 'string' or type(key) == 'number') and key or ('<' .. type(key) .. '-key>')
            out[safeKey] = walk(item, depth + 1)
        end
        seen[node] = nil
        return out
    end

    local ok, result = pcall(walk, value, 1)
    return ok and result or '<metadata-error>'
end

NEXM_INTERNAL.Modules.SafeData = SafeData
