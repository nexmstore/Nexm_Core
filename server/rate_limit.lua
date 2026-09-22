local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Ownership = NEXM_INTERNAL.Modules.Ownership
local PlayerCache = NEXM_INTERNAL.Modules.PlayerCache

local RateLimit = {}
local buckets = {}
local lastRaw, timerEpoch = nil, 0
local UINT32 = 4294967296

local function nowMs()
    if GetGameTimer then
        local raw = GetGameTimer()
        if raw < 0 then raw = raw + UINT32 end
        if lastRaw and raw < lastRaw and (lastRaw - raw) > 2147483648 then timerEpoch = timerEpoch + UINT32 end
        lastRaw = raw
        return timerEpoch + raw
    end
    return math.floor((os.clock and os.clock() or 0) * 1000)
end

local function optionsOrError(options)
    options = options or {}
    local limit = options.limit or 10
    local window = options.window or 10
    local ok, err = Validation.Integer(limit, { name = 'rate limit', min = 1, max = 100000 })
    if not ok then return nil, nil, err end
    ok, err = Validation.Number(window, { name = 'rate window', min = 0.05, max = 3600 })
    if not ok then return nil, nil, err end
    return limit, math.floor(window * 1000), nil
end

local function qualify(ownerResource, key)
    local ok, err = Ownership.ValidateLocalName(key)
    if not ok then return nil, err end
    return ownerResource .. ':' .. key, nil
end

local function bucketFor(source, key)
    buckets[source] = buckets[source] or {}
    return buckets[source], buckets[source][key]
end

function RateLimit.CheckInternal(source, qualifiedKey, options)
    local ok, err = Validation.Source(source)
    if not ok then return false, err end
    if type(qualifiedKey) ~= 'string' or qualifiedKey == '' or #qualifiedKey > 256 then
        return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Invalid rate-limit key')
    end
    local limit, windowMs, optionErr = optionsOrError(options)
    if optionErr then return false, optionErr end

    local map, bucket = bucketFor(source, qualifiedKey)
    local now = nowMs()
    local sessionScoped = not (options and options.sessionScoped == false)
    local sessionId = sessionScoped and PlayerCache.GetSession(source) or nil
    if not bucket or now >= bucket.expiresAt or (sessionScoped and bucket.sessionId ~= sessionId) then
        bucket = { count = 0, expiresAt = now + windowMs, sessionId = sessionId, sessionScoped = sessionScoped }
        map[qualifiedKey] = bucket
    end

    if bucket.count >= limit then
        return false, Errors.Create(Codes.RATE_LIMITED, 'Rate limit exceeded', {
            key = qualifiedKey, retryAfterMs = math.max(0, bucket.expiresAt - now)
        })
    end
    bucket.count = bucket.count + 1
    return true, nil
end

function RateLimit.Check(source, key, options, ownerResource)
    local owner = ownerResource or Ownership.Resolve()
    local qualified, err = qualify(owner, key)
    if not qualified then return false, err end
    return RateLimit.CheckInternal(source, qualified, options)
end

function RateLimit.Reset(source, key, ownerResource)
    local ok, err = Validation.Source(source)
    if not ok then return false, err end
    local owner = ownerResource or Ownership.Resolve()
    local qualified, keyErr = qualify(owner, key)
    if not qualified then return false, keyErr end
    if buckets[source] then buckets[source][qualified] = nil end
    return true, nil
end

function RateLimit.CleanupSource(source)
    buckets[source] = nil
end

function RateLimit.ResetSession(source)
    local map = buckets[source]
    if not map then return 0 end
    local removed = 0
    for key, bucket in pairs(map) do
        if bucket.sessionScoped ~= false then map[key] = nil; removed = removed + 1 end
    end
    if next(map) == nil then buckets[source] = nil end
    return removed
end

function RateLimit.CleanupOwner(ownerResource)
    local prefix, removed = ownerResource .. ':', 0
    for source, map in pairs(buckets) do
        for key in pairs(map) do
            if key:sub(1, #prefix) == prefix then map[key] = nil; removed = removed + 1 end
        end
        if next(map) == nil then buckets[source] = nil end
    end
    return removed
end

function RateLimit.CountBuckets()
    local count = 0
    for _, map in pairs(buckets) do for _ in pairs(map) do count = count + 1 end end
    return count
end

function RateLimit._NowMs() return nowMs() end
function RateLimit._Buckets() return buckets end

AddEventHandler('playerDropped', function() RateLimit.CleanupSource(tonumber(source)) end)
AddEventHandler('nexm_core:server:playerUnloaded', function(source) RateLimit.ResetSession(source) end)

NEXM_INTERNAL.Modules.RateLimit = RateLimit
