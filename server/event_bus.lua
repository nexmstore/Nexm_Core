local Validation = NEXM_INTERNAL.Modules.Validation
local NetworkValidation = NEXM_INTERNAL.Modules.NetworkValidation
local Errors = NEXM_INTERNAL.Modules.Errors
local Logger = NEXM_INTERNAL.Modules.Logger
local Ownership = NEXM_INTERNAL.Modules.Ownership
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Callable = NEXM_INTERNAL.Modules.Callable

local EventBus = {}
local listeners, nextId = {}, 0

local function validName(name)
    local ok = type(name) == 'string' and #name >= 3 and #name <= 128
        and name:match('^[%w_%-]+:[%w_:%._%-]+$') ~= nil
    if not ok then return false, Errors.Create(Codes.INVALID_EVENT_NAME, 'Internal event name must use an explicit domain prefix') end
    return true, nil
end

function EventBus.On(name, handler, ownerResource)
    local ok, err = validName(name); if not ok then return false, err end
    if not Callable.Is(handler) then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Internal event handler must be callable') end
    nextId = nextId + 1
    listeners[name] = listeners[name] or {}
    listeners[name][nextId] = {
        id = nextId, ownerResource = ownerResource or Ownership.Resolve(), callback = handler, registeredAt = os.time()
    }
    return true, nextId
end

function EventBus.Emit(name, payload)
    local ok, err = validName(name); if not ok then return false, err end
    local base, payloadErr = NetworkValidation.Request(payload)
    if payloadErr then return false, payloadErr end
    local group = listeners[name]
    if not group then return true, 0 end
    local ids = {}; for id in pairs(group) do ids[#ids + 1] = id end; table.sort(ids)
    local executed = 0
    for _, id in ipairs(ids) do
        local listener = group[id]
        if listener then
            local snapshot = NetworkValidation.Request(base)
            local callOk, rawErr = pcall(listener.callback, snapshot)
            executed = executed + 1
            if not callOk then
                local structured = Errors.Create(Codes.EVENT_HANDLER_ERROR, 'Internal event listener failed', {
                    event = name, ownerResource = listener.ownerResource, listenerId = id
                })
                Logger.Infrastructure(structured, 'event:' .. name, listener.ownerResource)
                if Config and Config.Debug then Logger.Debug('Internal event raw listener error', { rawError = tostring(rawErr) }, listener.ownerResource) end
            end
        end
    end
    return true, executed
end

function EventBus.CleanupOwner(ownerResource)
    local removed = 0
    for name, group in pairs(listeners) do
        for id, listener in pairs(group) do
            if listener.ownerResource == ownerResource then group[id] = nil; removed = removed + 1 end
        end
        if next(group) == nil then listeners[name] = nil end
    end
    return removed
end

function EventBus.CountListeners()
    local count = 0; for _, group in pairs(listeners) do for _ in pairs(group) do count = count + 1 end end; return count
end

NEXM_INTERNAL.Modules.EventBus = EventBus
