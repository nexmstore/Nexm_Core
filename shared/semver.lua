local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local SemVer = {}

local function invalid(value, reason)
    return nil, Errors.Create(
        Codes.INVALID_VERSION,
        'Invalid semantic version or constraint',
        { value = value, reason = reason }
    )
end

local function splitDot(value)
    local out = {}
    for part in value:gmatch('[^.]+') do
        out[#out + 1] = part
    end
    return out
end

local function hasEmptyIdentifier(value)
    return value:sub(1, 1) == '.'
        or value:sub(-1) == '.'
        or value:find('..', 1, true) ~= nil
end

local function parseCore(raw, allowPartial)
    if type(raw) ~= 'string' then
        return invalid(raw, 'version must be a string')
    end

    local text = raw:match('^%s*(.-)%s*$')
    if text == '' then
        return invalid(raw, 'version is empty')
    end

    local coreAndPre, build = text:match('^([^+]+)%+(.+)$')
    if not coreAndPre then
        coreAndPre = text
    end

    if build and (not build:match('^[0-9A-Za-z%-%.]+$') or hasEmptyIdentifier(build)) then
        return invalid(raw, 'invalid build metadata')
    end

    local core, prerelease = coreAndPre:match('^([^-]+)%-(.+)$')
    if not core then
        core = coreAndPre
    end

    if prerelease and (not prerelease:match('^[0-9A-Za-z%-%.]+$') or hasEmptyIdentifier(prerelease)) then
        return invalid(raw, 'invalid prerelease')
    end

    if hasEmptyIdentifier(core) then
        return invalid(raw, 'empty core version component')
    end

    local parts = splitDot(core)
    if (#parts < 1 or #parts > 3) or (not allowPartial and #parts ~= 3) then
        return invalid(raw, allowPartial and 'expected 1-3 numeric components' or 'expected major.minor.patch')
    end

    local numeric = { 0, 0, 0 }
    for index = 1, #parts do
        local part = parts[index]
        if not part:match('^%d+$') then
            return invalid(raw, 'core version components must be numeric')
        end
        if #part > 1 and part:sub(1, 1) == '0' then
            return invalid(raw, 'numeric components cannot contain leading zeros')
        end
        numeric[index] = tonumber(part)
    end

    local preParts = nil
    if prerelease then
        preParts = splitDot(prerelease)
        for _, part in ipairs(preParts) do
            if part == '' then
                return invalid(raw, 'empty prerelease identifier')
            end
            if part:match('^%d+$') and #part > 1 and part:sub(1, 1) == '0' then
                return invalid(raw, 'numeric prerelease identifiers cannot contain leading zeros')
            end
        end
    end

    return {
        major = numeric[1],
        minor = numeric[2],
        patch = numeric[3],
        prerelease = preParts,
        build = build,
        precision = #parts,
        raw = raw
    }
end

local function comparePrerelease(a, b)
    if not a and not b then
        return 0
    end
    if not a then
        return 1
    end
    if not b then
        return -1
    end

    local max = math.max(#a, #b)
    for index = 1, max do
        local left = a[index]
        local right = b[index]

        if left == nil then
            return -1
        end
        if right == nil then
            return 1
        end
        if left ~= right then
            local leftNumeric = left:match('^%d+$') ~= nil
            local rightNumeric = right:match('^%d+$') ~= nil

            if leftNumeric and rightNumeric then
                local ln, rn = tonumber(left), tonumber(right)
                if ln < rn then return -1 end
                if ln > rn then return 1 end
            elseif leftNumeric then
                return -1
            elseif rightNumeric then
                return 1
            else
                if left < right then return -1 end
                if left > right then return 1 end
            end
        end
    end

    return 0
end

local function compareParsed(a, b)
    if a.major ~= b.major then
        return a.major < b.major and -1 or 1
    end
    if a.minor ~= b.minor then
        return a.minor < b.minor and -1 or 1
    end
    if a.patch ~= b.patch then
        return a.patch < b.patch and -1 or 1
    end
    return comparePrerelease(a.prerelease, b.prerelease)
end

local function makeVersion(major, minor, patch)
    return {
        major = major,
        minor = minor,
        patch = patch,
        prerelease = nil,
        precision = 3
    }
end

function SemVer.Parse(version)
    return parseCore(version, false)
end

function SemVer.Compare(a, b)
    local left, leftErr = parseCore(a, false)
    if not left then
        return nil, leftErr
    end

    local right, rightErr = parseCore(b, false)
    if not right then
        return nil, rightErr
    end

    return compareParsed(left, right), nil
end

local function evaluateComparator(version, operator, target)
    local cmp = compareParsed(version, target)

    if operator == '=' or operator == '' then return cmp == 0 end
    if operator == '>' then return cmp > 0 end
    if operator == '>=' then return cmp >= 0 end
    if operator == '<' then return cmp < 0 end
    if operator == '<=' then return cmp <= 0 end

    return false
end

local function evaluateToken(version, token)
    local operator, rawTarget
    local prefixes = { '>=', '<=', '>', '<', '=', '~', '^' }
    for _, prefix in ipairs(prefixes) do
        if token:sub(1, #prefix) == prefix then
            operator = prefix
            rawTarget = token:sub(#prefix + 1)
            break
        end
    end

    if not operator then
        operator = '='
        rawTarget = token
    end

    if rawTarget == '' then
        return nil, Errors.Create(Codes.INVALID_VERSION, 'Missing semantic version after constraint operator', { token = token })
    end

    local target, err = parseCore(rawTarget, true)
    if not target then
        return nil, err
    end

    if operator == '~' then
        local upper
        if target.precision == 1 then
            upper = makeVersion(target.major + 1, 0, 0)
        else
            upper = makeVersion(target.major, target.minor + 1, 0)
        end
        return compareParsed(version, target) >= 0 and compareParsed(version, upper) < 0, nil
    end

    if operator == '^' then
        local upper
        if target.major > 0 then
            upper = makeVersion(target.major + 1, 0, 0)
        elseif target.minor > 0 then
            upper = makeVersion(0, target.minor + 1, 0)
        else
            upper = makeVersion(0, 0, target.patch + 1)
        end
        return compareParsed(version, target) >= 0 and compareParsed(version, upper) < 0, nil
    end

    return evaluateComparator(version, operator, target), nil
end

local function normalizeClause(clause)
    clause = clause:gsub(',', ' ')
    clause = clause:gsub('([<>~=%^]+)%s+', '%1')
    clause = clause:gsub('%s+', ' ')
    return clause:match('^%s*(.-)%s*$')
end

local function clauseMatches(version, clause)
    clause = normalizeClause(clause)
    if clause == '' or clause == '*' then
        return true, nil
    end

    local tokenCount = 0
    for token in clause:gmatch('%S+') do
        tokenCount = tokenCount + 1
        local ok, err = evaluateToken(version, token)
        if ok == nil then
            return nil, err
        end
        if not ok then
            return false, nil
        end
    end

    if tokenCount == 0 then
        return nil, Errors.Create(Codes.INVALID_VERSION, 'Empty semantic version constraint', { constraint = clause })
    end

    return true, nil
end

local function splitOrClauses(constraint)
    if constraint:find('|', 1, true) and not constraint:find('||', 1, true) then
        return nil, Errors.Create(Codes.INVALID_VERSION, 'Use || for OR semantic version constraints', { constraint = constraint })
    end

    local clauses = {}
    local startAt = 1
    while true do
        local from, to = constraint:find('||', startAt, true)
        if not from then
            clauses[#clauses + 1] = constraint:sub(startAt)
            break
        end
        clauses[#clauses + 1] = constraint:sub(startAt, from - 1)
        startAt = to + 1
    end
    return clauses, nil
end

function SemVer.Satisfies(version, constraint)
    local parsedVersion, versionErr = parseCore(version, false)
    if not parsedVersion then
        return false, versionErr
    end

    if type(constraint) ~= 'string' then
        return false, Errors.Create(Codes.INVALID_VERSION, 'Constraint must be a string', { constraint = constraint })
    end

    local clauses, splitErr = splitOrClauses(constraint)
    if not clauses then return false, splitErr end

    local hadClause = false
    for _, clause in ipairs(clauses) do
        clause = clause:match('^%s*(.-)%s*$')
        if clause ~= '' then
            hadClause = true
            local ok, err = clauseMatches(parsedVersion, clause)
            if ok == nil then
                return false, err
            end
            if ok then
                return true, nil
            end
        end
    end

    if not hadClause then
        return false, Errors.Create(Codes.INVALID_VERSION, 'Constraint is empty', { constraint = constraint })
    end

    return false, nil
end

NEXM_INTERNAL.Modules.SemVer = SemVer
