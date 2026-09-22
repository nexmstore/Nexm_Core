local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local Validation = {}


local Callable = {}

-- FiveM serializes cross-resource Lua functions as callable function-reference
-- tables (__cfx_functionReference + __call). Treat those as functions for
-- server/client registration APIs without widening the public validation API.
function Callable.Is(value)
    if type(value) == 'function' then return true end
    if type(value) ~= 'table' or rawget(value, '__cfx_functionReference') == nil then return false end
    local mt = getmetatable(value)
    return type(mt) == 'table' and type(mt.__call) == 'function'
end

NEXM_INTERNAL.Modules.Callable = Callable

local function fail(name, expected, value, extra)
    local context = {
        field = name,
        expected = expected,
        actualType = type(value)
    }

    if type(extra) == 'table' then
        for key, item in pairs(extra) do
            context[key] = item
        end
    end

    return false, Errors.Create(
        Codes.INVALID_ARGUMENT,
        ('Invalid %s'):format(name or 'value'),
        context
    )
end

local function required(value, options)
    return not (options and options.required == false) or value ~= nil
end

local function isFinite(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function Validation.String(value, options)
    options = options or {}
    local name = options.name or 'string'

    if value == nil and options.required == false then
        return true, nil, nil
    end

    if type(value) ~= 'string' then
        return fail(name, 'string', value)
    end

    local length = #value
    if options.min and length < options.min then
        return fail(name, ('string length >= %d'):format(options.min), value, { length = length })
    end

    if options.max and length > options.max then
        return fail(name, ('string length <= %d'):format(options.max), value, { length = length })
    end

    if options.nonEmpty and value == '' then
        return fail(name, 'non-empty string', value)
    end

    if options.pattern and not value:match(options.pattern) then
        return fail(name, ('string matching %s'):format(options.pattern), value)
    end

    if options.allowed then
        local found = false
        for _, allowed in ipairs(options.allowed) do
            if value == allowed then
                found = true
                break
            end
        end

        if not found then
            return fail(name, 'allowed string value', value)
        end
    end

    return true, nil, value
end

function Validation.Number(value, options)
    options = options or {}
    local name = options.name or 'number'

    if value == nil and options.required == false then
        return true, nil, nil
    end

    if not isFinite(value) then
        return fail(name, 'finite number', value)
    end

    if options.min and value < options.min then
        return fail(name, ('number >= %s'):format(options.min), value)
    end

    if options.max and value > options.max then
        return fail(name, ('number <= %s'):format(options.max), value)
    end

    return true, nil, value
end

function Validation.Integer(value, options)
    local ok, err = Validation.Number(value, options)
    if not ok then
        return false, err
    end

    if value == nil and options and options.required == false then
        return true, nil, nil
    end

    if value % 1 ~= 0 then
        return fail((options and options.name) or 'integer', 'integer', value)
    end

    return true, nil, value
end

function Validation.Boolean(value, options)
    options = options or {}
    local name = options.name or 'boolean'

    if value == nil and options.required == false then
        return true, nil, nil
    end

    if type(value) ~= 'boolean' then
        return fail(name, 'boolean', value)
    end

    return true, nil, value
end

function Validation.Table(value, options)
    options = options or {}
    local name = options.name or 'table'

    if value == nil and options.required == false then
        return true, nil, nil
    end

    if type(value) ~= 'table' then
        return fail(name, 'table', value)
    end

    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end

    if options.minEntries and count < options.minEntries then
        return fail(name, ('table entries >= %d'):format(options.minEntries), value, { entries = count })
    end

    if options.maxEntries and count > options.maxEntries then
        return fail(name, ('table entries <= %d'):format(options.maxEntries), value, { entries = count })
    end

    return true, nil, value
end

function Validation.Identifier(value, options)
    options = options or {}
    options.name = options.name or 'identifier'
    options.nonEmpty = true
    options.min = options.min or 1
    options.max = options.max or ((Config and Config.Security and Config.Security.maxIdentifierLength) or 128)
    options.pattern = options.pattern or '^[%w%._:%-]+$'

    return Validation.String(value, options)
end

function Validation.Source(value, options)
    options = options or {}
    options.name = options.name or 'source'
    options.min = options.allowConsole and 0 or 1
    options.max = options.max or 65535

    return Validation.Integer(value, options)
end

function Validation.Coordinates(value, options)
    options = options or {}
    local name = options.name or 'coordinates'

    if value == nil and options.required == false then
        return true, nil, nil
    end

    local x, y, z
    local valueType = type(value)

    if valueType == 'vector3' then
        x, y, z = value.x, value.y, value.z
    elseif valueType == 'table' then
        x, y, z = value.x or value[1], value.y or value[2], value.z or value[3]
    else
        return fail(name, 'vector3 or coordinate table', value)
    end

    if not isFinite(x) or not isFinite(y) or not isFinite(z) then
        return fail(name, 'finite x/y/z coordinates', value)
    end

    local maxAbs = options.maxAbs
    if maxAbs and (math.abs(x) > maxAbs or math.abs(y) > maxAbs or math.abs(z) > maxAbs) then
        return fail(name, ('coordinates within ±%s'):format(maxAbs), value)
    end

    return true, nil, { x = x, y = y, z = z }
end


function Validation.SerializableTable(value, options)
    options = options or {}
    local name = options.name or 'table'
    if value == nil and options.required == false then return true, nil, nil end
    if type(value) ~= 'table' then return fail(name, 'serializable table', value) end

    local maxDepth = options.maxDepth or ((Config and Config.Security and Config.Security.maxTableDepth) or 12)
    local maxEntries = options.maxEntries or ((Config and Config.Security and Config.Security.maxTableEntries) or 2048)
    local seen, entries = {}, 0

    local function walk(node, depth, path)
        if depth > maxDepth then
            return false, Errors.Create(Codes.INVALID_ARGUMENT, ('Invalid %s'):format(name), {
                field = name, expected = ('table depth <= %d'):format(maxDepth), path = path
            })
        end
        if seen[node] then
            return false, Errors.Create(Codes.INVALID_ARGUMENT, ('Invalid %s'):format(name), {
                field = name, expected = 'acyclic serializable table', path = path
            })
        end
        seen[node] = true
        for key, item in pairs(node) do
            entries = entries + 1
            if entries > maxEntries then
                seen[node] = nil
                return false, Errors.Create(Codes.INVALID_ARGUMENT, ('Invalid %s'):format(name), {
                    field = name, expected = ('table entries <= %d'):format(maxEntries), entries = entries
                })
            end
            local kt = type(key)
            if kt ~= 'string' and kt ~= 'number' then
                seen[node] = nil
                return false, Errors.Create(Codes.INVALID_ARGUMENT, ('Invalid %s'):format(name), {
                    field = name, expected = 'string/number table keys', path = path, actualType = kt
                })
            end
            local t = type(item)
            if t == 'table' then
                local ok, err = walk(item, depth + 1, path .. '.' .. tostring(key))
                if not ok then seen[node] = nil; return false, err end
            elseif t ~= 'string' and t ~= 'number' and t ~= 'boolean' and t ~= 'nil' then
                seen[node] = nil
                return false, Errors.Create(Codes.INVALID_ARGUMENT, ('Invalid %s'):format(name), {
                    field = name, expected = 'JSON-like serializable values', path = path .. '.' .. tostring(key), actualType = t
                })
            elseif t == 'number' and not isFinite(item) then
                seen[node] = nil
                return false, Errors.Create(Codes.INVALID_ARGUMENT, ('Invalid %s'):format(name), {
                    field = name, expected = 'finite numeric metadata', path = path .. '.' .. tostring(key)
                })
            end
        end
        seen[node] = nil
        return true, nil
    end

    local ok, err = walk(value, 1, name)
    if not ok then return false, err end
    return true, nil, value
end

function Validation.Finite(value)
    return isFinite(value)
end

NEXM_INTERNAL.Modules.Validation = Validation
