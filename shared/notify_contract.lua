local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local SafeData = NEXM_INTERNAL.Modules.SafeData
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local SemVer = NEXM_INTERNAL.Modules.SemVer

local NotifyContract = {}
local types = { info=true, success=true, warning=true, error=true }

function NotifyContract.ValidatePayload(message, notifyType, duration, options)
    local cfg = Config and Config.NotifyDefaults or {}
    local ok, err = Validation.String(message, {
        name='notification message', nonEmpty=true, min=1, max=cfg.maxMessageLength or 2048
    }); if not ok then return nil, err end
    notifyType = notifyType or cfg.type or 'info'
    if type(notifyType) ~= 'string' or not types[notifyType] then
        return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'Invalid notification type', { type = notifyType })
    end
    duration = duration or cfg.duration or 5000
    ok, err = Validation.Integer(duration, {
        name='notification duration', min=cfg.minDuration or 500, max=cfg.maxDuration or 60000
    }); if not ok then return nil, err end
    if options == nil then options = {} end
    if type(options) ~= 'table' then return nil, Errors.Create(Codes.INVALID_ARGUMENT, 'Notification options must be a table') end
    local copied, copyErr = SafeData.Copy(options, { field='notification options', maxDepth=4, maxEntries=64, maxTotalNodes=128, maxStringLength=1024, maxKeyLength=64 })
    if copyErr then return nil, copyErr end
    if copied.title ~= nil then
        ok, err = Validation.String(copied.title, { name='notification title', nonEmpty=true, max=cfg.maxTitleLength or 128 })
        if not ok then return nil, err end
    end
    return { message=message, type=notifyType, duration=duration, options=copied }, nil
end

function NotifyContract.ValidateAdapter(adapter)
    if type(adapter) ~= 'table' or type(adapter.metadata) ~= 'table' then
        return false, Errors.Create(Codes.INVALID_NOTIFY_ADAPTER, 'Notify adapter metadata is required')
    end
    local m = adapter.metadata
    local ok, err = Validation.String(m.name, { name='notify adapter name', nonEmpty=true, max=64, pattern='^[%w_%-]+$' }); if not ok then return false, Errors.Create(Codes.INVALID_NOTIFY_ADAPTER, err.message) end
    local parsed, versionErr = SemVer.Parse(m.version or '')
    if not parsed then return false, Errors.Create(Codes.INVALID_NOTIFY_ADAPTER, 'Notify adapter version must be valid SemVer', { adapter=m.name }) end
    ok, err = Validation.String(m.resource, { name='notify adapter resource', nonEmpty=true, max=128, pattern='^[%w%._%-]+$' }); if not ok then return false, Errors.Create(Codes.INVALID_NOTIFY_ADAPTER, err.message) end
    if m.critical ~= false then return false, Errors.Create(Codes.INVALID_NOTIFY_ADAPTER, 'Notify adapters must declare critical=false') end
    if type(m.capabilities) ~= 'table' then return false, Errors.Create(Codes.INVALID_NOTIFY_ADAPTER, 'Notify adapter capabilities must be a table') end
    for _, method in ipairs({'IsAvailable','Initialize','Shutdown','GetState','Send'}) do
        if type(adapter[method]) ~= 'function' then return false, Errors.Create(Codes.INVALID_NOTIFY_ADAPTER, 'Notify adapter is missing required method', { method=method, adapter=m.name }) end
    end
    return true, nil
end

NEXM_INTERNAL.Modules.NotifyContract = NotifyContract
