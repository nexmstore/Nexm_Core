local Constants = NEXM_INTERNAL.Modules.Constants

local Errors = {}

local function copy(value, seen)
    if type(value) ~= 'table' then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return '<cycle>'
    end

    seen[value] = true
    local out = {}
    for key, item in pairs(value) do
        out[copy(key, seen)] = copy(item, seen)
    end
    seen[value] = nil
    return out
end

function Errors.Create(code, message, context)
    local normalizedCode = type(code) == 'string' and code or Constants.ERROR_CODES.INVALID_ARGUMENT
    local normalizedMessage = type(message) == 'string' and message or 'NEXM Core error'

    return {
        code = normalizedCode,
        message = normalizedMessage,
        context = type(context) == 'table' and copy(context) or {}
    }
end

function Errors.Wrap(code, message, cause, context)
    local wrappedContext = type(context) == 'table' and copy(context) or {}

    if type(cause) == 'table' and type(cause.code) == 'string' then
        wrappedContext.causeCode = cause.code
    end

    return Errors.Create(code, message, wrappedContext)
end

function Errors.Is(value, code)
    return type(value) == 'table'
        and type(value.code) == 'string'
        and (code == nil or value.code == code)
end

function Errors.Copy(value)
    if not Errors.Is(value) then
        return nil
    end

    return copy(value)
end

NEXM_INTERNAL.Modules.Errors = Errors
