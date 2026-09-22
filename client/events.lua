local State = NEXM_INTERNAL.Modules.ClientPlayerState
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Callable = NEXM_INTERNAL.Modules.Callable

local ClientEvents = {}
local subscribers = { playerLoaded = {}, playerUnloaded = {}, jobChanged = {}, dutyChanged = {} }
local nextId = 0

local function owner()
    local invoking = GetInvokingResource and GetInvokingResource() or nil
    return invoking and invoking ~= '' and invoking or (GetCurrentResourceName and GetCurrentResourceName() or 'nexm_core')
end
local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}; if seen[value] then return '<cycle>' end; seen[value] = true
    local out = {}; for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end; seen[value] = nil; return out
end
local function emit(kind, ...)
    for _, subscription in pairs(subscribers[kind] or {}) do
        local ok, err = pcall(subscription.callback, ...)
        if not ok then print(('[NEXM][CLIENT][ERROR][%s] lifecycle callback failed: %s'):format(subscription.ownerResource, tostring(err))) end
    end
end
function ClientEvents.Subscribe(kind, callback, ownerResource)
    if not subscribers[kind] or not Callable.Is(callback) then
        return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Invalid client lifecycle subscription', { event = kind })
    end
    nextId = nextId + 1
    subscribers[kind][nextId] = { id = nextId, ownerResource = ownerResource or owner(), callback = callback }
    return true, nextId
end
function ClientEvents.CleanupOwner(ownerResource)
    local removed = 0
    for _, group in pairs(subscribers) do
        for id, item in pairs(group) do if item.ownerResource == ownerResource then group[id] = nil; removed = removed + 1 end end
    end
    return removed
end

RegisterNetEvent('nexm_core:client:playerState', function(snapshot)
    local before = State.Get()
    State.Set(snapshot)
    local after = State.Get()
    if not before and after then emit('playerLoaded', copy(after)) return end
    if before and after then
        local oldJob, newJob = before.job, after.job
        if oldJob and newJob then
            local changed = oldJob.name ~= newJob.name or oldJob.grade ~= newJob.grade or oldJob.label ~= newJob.label or oldJob.gradeName ~= newJob.gradeName
            if changed then emit('jobChanged', copy(oldJob), copy(newJob)) end
            if oldJob.onDuty ~= newJob.onDuty then emit('dutyChanged', oldJob.onDuty, newJob.onDuty, copy(newJob)) end
        end
    end
end)

RegisterNetEvent('nexm_core:client:playerUnloaded', function(reason)
    local before = State.Get()
    if not before then return end
    emit('playerUnloaded', copy(before), reason)
    State.Clear()
end)

RegisterNetEvent('nexm_core:client:frameworkUnavailable', function()
    local before = State.Get()
    if before then emit('playerUnloaded', copy(before), 'framework_unavailable') end
    State.Clear()
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then ClientEvents.CleanupOwner(resourceName) end
end)

NEXM_INTERNAL.Modules.ClientEvents = ClientEvents

-- Request an authoritative safe local snapshot after client handlers exist.
-- No identity/job data is sent from the client.
TriggerServerEvent('nexm_core:server:requestLocalState')
