local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local Locale = {}
local registry, fallbacks, missingWarned = {}, {}, {}

local function validateLocale(locale)
    return Validation.String(locale, {
        name = 'locale', nonEmpty = true, min = 2, max = 16,
        pattern = '^[%a][%w_%-]*$'
    })
end

local function validateKey(key)
    return Validation.String(key, {
        name = 'locale key', nonEmpty = true, min = 1, max = 128,
        pattern = '^[%a_][%w_%.%-]*$'
    })
end

local function flatten(input, prefix, out, depth, seen)
    if depth > 8 then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Locale table exceeds maximum nesting depth') end
    if seen[input] then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Locale table contains a cycle') end
    seen[input] = true
    for key, value in pairs(input) do
        if type(key) ~= 'string' then seen[input] = nil; return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Locale keys must be strings') end
        local full = prefix and (prefix .. '.' .. key) or key
        local ok, err = validateKey(full); if not ok then seen[input] = nil; return false, err end
        if type(value) == 'table' then
            local nestedOk, nestedErr = flatten(value, full, out, depth + 1, seen)
            if not nestedOk then seen[input] = nil; return false, nestedErr end
        elseif type(value) == 'string' then
            local valueOk, valueErr = Validation.String(value, { name = 'locale value', max = 8192 })
            if not valueOk then seen[input] = nil; return false, valueErr end
            out[full] = value
        else
            seen[input] = nil
            return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Locale values must be strings or nested tables', { key = full, actualType = type(value) })
        end
    end
    seen[input] = nil
    return true, nil
end

local function warnMissing(owner, locale, key)
    if not Config or not Config.Debug then return end
    local token = table.concat({owner, locale, key}, '|')
    if missingWarned[token] then return end
    missingWarned[token] = true
    local logger = NEXM_INTERNAL.Modules.Logger
    if logger and logger.Warn then
        logger.Warn('Missing locale key', { locale = locale, key = key }, owner)
    else
        print(('[NEXM][LOCALE][WARN][%s] missing %s:%s'):format(owner, locale, key))
    end
end

function Locale.Register(locale, strings, ownerResource)
    local ok, err = validateLocale(locale); if not ok then return false, err end
    if type(strings) ~= 'table' then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Locale registration must be a table') end
    local owner = ownerResource or 'nexm_core'
    local flat = {}
    ok, err = flatten(strings, nil, flat, 1, {})
    if not ok then return false, err end
    registry[owner] = registry[owner] or {}
    registry[owner][locale] = registry[owner][locale] or {}
    local target = registry[owner][locale]
    for key in pairs(flat) do
        if target[key] ~= nil then
            return false, Errors.Create(Codes.REGISTRATION_EXISTS, 'Locale key is already registered', { ownerResource = owner, locale = locale, key = key })
        end
    end
    for key, value in pairs(flat) do target[key] = value end
    return true, nil
end

function Locale.SetFallback(locale, ownerResource)
    local ok, err = validateLocale(locale); if not ok then return false, err end
    fallbacks[ownerResource or 'nexm_core'] = locale
    return true, nil
end

local function scalar(value)
    local t = type(value)
    if t == 'string' then return value end
    if t == 'number' then return Validation.Finite(value) and tostring(value) or '<invalid>' end
    if t == 'boolean' then return value and 'true' or 'false' end
    if t == 'nil' then return nil end
    return '<unsupported>'
end

local function interpolate(text, vars)
    if type(vars) ~= 'table' then return text end
    return (text:gsub('{([%a_][%w_]*)}', function(name)
        local value = scalar(rawget(vars, name))
        return value == nil and ('{' .. name .. '}') or value
    end))
end

function Locale.Get(key, vars, ownerResource, requestedLocale)
    local keyOk, keyErr = validateKey(key); if not keyOk then return nil, keyErr end
    if vars ~= nil and type(vars) ~= 'table' then return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'Locale interpolation variables must be a table') end
    local owner = ownerResource or 'nexm_core'
    local requested = requestedLocale or (Config and Config.Locale) or 'en'
    local candidates, seen = {}, {}
    local function add(locale)
        if type(locale) == 'string' and locale ~= '' and not seen[locale] then seen[locale] = true; candidates[#candidates + 1] = locale end
    end
    add(requested)
    add(fallbacks[owner])
    add(Config and Config.LocaleFallback)
    add('en')
    for _, locale in ipairs(candidates) do
        local text = registry[owner] and registry[owner][locale] and registry[owner][locale][key]
        if text ~= nil then return interpolate(text, vars), nil end
    end
    warnMissing(owner, requested, key)
    return key, nil
end

function Locale.GetRegistered(ownerResource)
    local owner = ownerResource or 'nexm_core'
    local out = {}
    for locale, strings in pairs(registry[owner] or {}) do
        out[locale] = {}
        for key, value in pairs(strings) do out[locale][key] = value end
    end
    return out
end

function Locale.CleanupOwner(ownerResource)
    local removed = 0
    for _, strings in pairs(registry[ownerResource] or {}) do for _ in pairs(strings) do removed = removed + 1 end end
    registry[ownerResource] = nil
    fallbacks[ownerResource] = nil
    for token in pairs(missingWarned) do if token:sub(1, #ownerResource + 1) == ownerResource .. '|' then missingWarned[token] = nil end end
    return removed
end

NEXM_INTERNAL.Modules.Locale = Locale
