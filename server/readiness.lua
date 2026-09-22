local Ownership = NEXM_INTERNAL.Modules.Ownership
local Logger = NEXM_INTERNAL.Modules.Logger
local State = NEXM_INTERNAL.Modules.State
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Callable = NEXM_INTERNAL.Modules.Callable

local Readiness = {}
local subscribers = {}
local nextId = 0
local emitted = false

local function execute(subscription)
    local ok, rawError = pcall(subscription.callback)
    if ok then return true, nil end

    local err = Errors.Create(Codes.READY_CALLBACK_ERROR, 'Dependent resource ready callback failed', {
        ownerResource = subscription.ownerResource,
        subscriptionId = subscription.id
    })
    Logger.Infrastructure(err, 'readiness', subscription.ownerResource)
    if Config and Config.Debug then
        Logger.Debug('Ready callback raw error', { rawError = tostring(rawError) }, subscription.ownerResource)
    end
    return false, err
end

function Readiness.IsReady() return State.IsReady() end

function Readiness.Subscribe(callback, ownerResource)
    if not Callable.Is(callback) then
        return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Ready callback must be a function')
    end

    local owner = ownerResource or Ownership.Resolve()
    nextId = nextId + 1
    local subscription = {
        id = nextId,
        ownerResource = owner,
        registeredAt = os.time(),
        callback = callback
    }

    if State.IsReady() then
        execute(subscription)
        return true, subscription.id
    end

    subscribers[subscription.id] = subscription
    return true, subscription.id
end

function Readiness.MarkReady()
    if emitted then return end
    emitted = true
    TriggerEvent('nexm_core:server:ready')
    local EventBus = NEXM_INTERNAL.Modules.EventBus
    if EventBus and EventBus.Emit then EventBus.Emit('core:ready', { state = 'READY' }) end

    local pending = subscribers
    subscribers = {}
    local ids = {}
    for id in pairs(pending) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do execute(pending[id]) end
end

function Readiness.CleanupOwner(ownerResource)
    local removed = 0
    for id, subscription in pairs(subscribers) do
        if subscription.ownerResource == ownerResource then
            subscribers[id] = nil
            removed = removed + 1
        end
    end
    return removed
end

NEXM_INTERNAL.Modules.Readiness = Readiness
