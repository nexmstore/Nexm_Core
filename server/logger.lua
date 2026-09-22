local Logger = {}
local Errors = NEXM_INTERNAL.Modules.Errors
local SafeData = NEXM_INTERNAL.Modules.SafeData

local levels = { debug = 10, info = 20, warn = 30, error = 40 }
local suppression = {}

local function nowMs()
    if GetGameTimer then
        local ok, value = pcall(GetGameTimer)
        if ok and type(value) == 'number' then return value % 4294967296 end
    end
    return math.floor((os.clock and os.clock() or os.time()) * 1000)
end

local function elapsed(now, before)
    if now >= before then return now - before end
    return (4294967296 - before) + now
end

local function currentResource()
    local invoking = GetInvokingResource and GetInvokingResource() or nil
    if invoking and invoking ~= '' then return invoking end
    return GetCurrentResourceName and GetCurrentResourceName() or 'nexm_core'
end

local function threshold()
    local cfg = Config and Config.Logging or {}
    local configured = cfg.Level or cfg.level or 'info'
    return levels[string.lower(tostring(configured))] or levels.info
end

function Logger.IsEnabled(level)
    local n = levels[string.lower(tostring(level or ''))]
    return n ~= nil and n >= threshold()
end

local function sanitizeMetadata(metadata)
    if type(metadata) ~= 'table' then return nil end
    local safe = SafeData.ForLog(metadata, { maxDepth=6, maxEntries=128, maxTotalNodes=384, maxStringLength=1024, maxKeyLength=96 })
    if type(safe) ~= 'table' then return { value = safe } end
    if not (Config and Config.Debug) then
        safe.stack = nil; safe.traceback = nil; safe.queryParameters = nil; safe.rawError = nil
    end
    return safe
end

local function encodeMetadata(metadata)
    local safe = sanitizeMetadata(metadata)
    if not safe or next(safe) == nil then return '' end
    local ok, encoded = pcall(function() return json.encode(safe) end)
    if not ok then return ' metadata=<unserializable>' end
    local cfg = Config and Config.Logging or {}
    local maxLength = cfg.maxMetadataLength or 2000
    if #encoded > maxLength then encoded = encoded:sub(1, maxLength) .. '...' end
    return ' metadata=' .. encoded
end

local function shouldSuppress(level, owner, message, metadata)
    if level ~= 'warn' and level ~= 'error' then return false, nil end
    local code = type(metadata)=='table' and type(metadata.error)=='table' and metadata.error.code or ''
    local component = type(metadata)=='table' and metadata.component or ''
    local key = table.concat({ owner, level, tostring(component), tostring(code), message }, '|')
    local cfg=Config and Config.Logging or {}
    local window = cfg.repeatedErrorWindowMs or 10000
    local now = nowMs(); local record=suppression[key]
    if record and elapsed(now, record.lastPrintedAt) < window then record.suppressed=record.suppressed+1; return true,nil end
    local count=record and record.suppressed or 0
    suppression[key]={lastPrintedAt=now,suppressed=0}
    return false,count
end

local function emit(level, message, metadata, ownerResource)
    local ok, err = pcall(function()
        level=string.lower(tostring(level))
        if not Logger.IsEnabled(level) then return end
        local owner=ownerResource or currentResource()
        local text=type(message)=='string' and message or tostring(message)
        local suppress,previous=shouldSuppress(level,owner,text,metadata)
        if suppress then return end
        if previous and previous>0 then print(('[NEXM][WARN][%s] Suppressed %d repeated log message(s).'):format(owner,previous)) end
        local timestamp=os.date('!%Y-%m-%dT%H:%M:%SZ')
        print(('[NEXM][%s][%s][%s] %s%s'):format(string.upper(level),owner,timestamp,text,encodeMetadata(metadata)))
    end)
    if not ok then
        pcall(print,('[NEXM][LOGGER][FAILSAFE] logging failed: %s'):format(tostring(err)))
    end
end

function Logger.Debug(message,metadata,ownerResource) emit('debug',message,metadata,ownerResource) end
function Logger.Info(message,metadata,ownerResource) emit('info',message,metadata,ownerResource) end
function Logger.Warn(message,metadata,ownerResource) emit('warn',message,metadata,ownerResource) end
function Logger.Error(message,metadata,ownerResource) emit('error',message,metadata,ownerResource) end
function Logger.Infrastructure(err,component,ownerResource)
    if not Errors.Is(err) then return end
    Logger.Error(('Infrastructure failure in %s: %s'):format(component or 'unknown',err.message),{error=err,component=component},ownerResource)
end
function Logger.ResetSuppressionForTests() suppression={} end

NEXM_INTERNAL.Modules.Logger=Logger
