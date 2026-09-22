local Framework = NEXM_INTERNAL.Managers.Framework
local Cache = NEXM_INTERNAL.Modules.PlayerCache
local Player = NEXM_INTERNAL.Modules.Player
local Ownership = NEXM_INTERNAL.Modules.Ownership
local Errors = NEXM_INTERNAL.Modules.Errors
local Logger = NEXM_INTERNAL.Modules.Logger
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Callable = NEXM_INTERNAL.Modules.Callable

local Lifecycle = {}
local subscribers = { playerLoaded = {}, playerUnloaded = {}, jobChanged = {}, dutyChanged = {} }
local nextSubscriptionId = 0
local globalInitialized = false
local unloading = {}

local function clientSnapshot(snapshot)
    if not snapshot then return nil end
    local job = snapshot.job and {
        name = snapshot.job.name, label = snapshot.job.label, grade = snapshot.job.grade,
        gradeName = snapshot.job.gradeName, onDuty = snapshot.job.onDuty
    } or nil
    return {
        identifier = snapshot.identifier,
        name = snapshot.name,
        job = job,
        framework = snapshot.framework,
        loaded = snapshot.loaded == true
    }
end

local function emit(kind, ...)
    local group = subscribers[kind]
    if not group then return end
    local ids = {}
    for id in pairs(group) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local subscription = group[id]
        if subscription then
            local ok, rawError = pcall(subscription.callback, ...)
            if not ok then
                local err = Errors.Create(Codes.LIFECYCLE_CALLBACK_ERROR, 'Normalized lifecycle subscriber failed', {
                    ownerResource = subscription.ownerResource,
                    event = kind,
                    subscriptionId = id
                })
                Logger.Infrastructure(err, 'lifecycle:' .. kind, subscription.ownerResource)
                if Config and Config.Debug then
                    Logger.Debug('Lifecycle callback raw error', { rawError = tostring(rawError) }, subscription.ownerResource)
                end
            end
        end
    end
end

function Lifecycle.Subscribe(kind, callback, ownerResource)
    if not subscribers[kind] then
        return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Unknown lifecycle event', { event = kind })
    end
    if not Callable.Is(callback) then
        return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Lifecycle callback must be a function', { event = kind })
    end
    nextSubscriptionId = nextSubscriptionId + 1
    local owner = ownerResource or Ownership.Resolve()
    subscribers[kind][nextSubscriptionId] = {
        id = nextSubscriptionId, ownerResource = owner, registeredAt = os.time(), callback = callback
    }
    return true, nextSubscriptionId
end

function Lifecycle.CleanupOwner(ownerResource)
    local removed = 0
    for _, group in pairs(subscribers) do
        for id, subscription in pairs(group) do
            if subscription.ownerResource == ownerResource then group[id] = nil; removed = removed + 1 end
        end
    end
    return removed
end

local function jobsEqualExceptDuty(a, b)
    if a == nil or b == nil then return a == b end
    return a.name == b.name and a.label == b.label and a.grade == b.grade and a.gradeName == b.gradeName
end

local function sendState(source, snapshot)
    if TriggerClientEvent then TriggerClientEvent('nexm_core:client:playerState', source, clientSnapshot(snapshot)) end
end

function Lifecycle.HandlePlayerLoaded(source, options)
    source = tonumber(source)
    if not source or source <= 0 then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Invalid player source for lifecycle load', { source = source }) end
    local adapter, frameworkErr = Framework.RequireHealthy(); if not adapter then return false, frameworkErr end

    local existing = Cache.Get(source)
    if existing then
        local raw, rawErr = adapter.GetCharacterIdentifier(source)
        if raw and existing.identity and tostring(raw) == tostring(existing.identity.character) then
            sendState(source, existing)
            return true, existing
        end
        if rawErr and rawErr.code ~= Codes.PLAYER_NOT_FOUND then Logger.Infrastructure(rawErr, 'framework:identity', 'nexm_core') end
        Lifecycle.HandlePlayerUnloaded(source, 'character_replaced')
    end

    local snapshot, snapshotErr = Player.BuildSnapshot(source, adapter)
    if not snapshot then
        if snapshotErr and snapshotErr.code ~= Codes.PLAYER_NOT_FOUND and snapshotErr.code ~= Codes.UNSUPPORTED_FEATURE then
            Logger.Infrastructure(snapshotErr, 'framework:player_snapshot', 'nexm_core')
        end
        return false, snapshotErr
    end
    local sessionId, cacheErr = Cache.Store(source, snapshot)
    if not sessionId then Logger.Infrastructure(cacheErr, 'player_cache', 'nexm_core'); return false, cacheErr end

    sendState(source, snapshot)
    options = options or {}
    if options.emit ~= false and not options.reconstructed then
        emit('playerLoaded', source, Cache.Get(source))
        TriggerEvent('nexm_core:server:playerLoaded', source, Cache.Get(source))
    end
    return true, { snapshot = Cache.Get(source), characterSessionId = sessionId, reconstructed = options.reconstructed == true }
end

function Lifecycle.HandlePlayerUnloaded(source, reason)
    source = tonumber(source)
    local internal = source and Cache.GetInternal(source) or nil
    if not internal then return false, nil end
    local sessionId = internal.characterSessionId
    if unloading[source] == sessionId then return false, nil end
    unloading[source] = sessionId

    local snapshot = Cache.Get(source)
    emit('playerUnloaded', source, snapshot, reason)
    TriggerEvent('nexm_core:server:playerUnloaded', source, snapshot, reason)
    Cache.Remove(source)
    unloading[source] = nil
    if TriggerClientEvent then TriggerClientEvent('nexm_core:client:playerUnloaded', source, reason) end
    return true, nil
end

local function synchronizeJob(source, allowJobEvent, allowDutyEvent)
    source = tonumber(source)
    local sessionId = source and Cache.GetSession(source) or nil
    if not sessionId then return false, nil end
    local adapter, frameworkErr = Framework.RequireHealthy(); if not adapter then return false, frameworkErr end
    local newJob, jobErr = adapter.GetJob(source)
    if not newJob then
        if jobErr and jobErr.code ~= Codes.PLAYER_NOT_FOUND then Logger.Infrastructure(jobErr, 'framework:job', 'nexm_core') end
        return false, jobErr
    end
    if not Cache.IsCurrentSession(source, sessionId) then
        return false, Errors.Create(Codes.STALE_CHARACTER_SESSION, 'Ignored stale job update after character session changed', {
            source = source, expectedSession = sessionId, currentSession = Cache.GetSession(source)
        })
    end

    local before = Cache.Get(source)
    local oldJob = before and before.job or nil
    local ok, oldOrErr = Cache.UpdateJob(source, newJob, sessionId)
    if not ok then return false, oldOrErr end
    local after = Cache.Get(source)

    if allowJobEvent and not jobsEqualExceptDuty(oldJob, newJob) then
        emit('jobChanged', source, oldJob, after.job)
        TriggerEvent('nexm_core:server:jobChanged', source, oldJob, after.job)
    end
    if allowDutyEvent and oldJob and oldJob.onDuty ~= newJob.onDuty then
        emit('dutyChanged', source, oldJob.onDuty, newJob.onDuty, after.job)
        TriggerEvent('nexm_core:server:dutyChanged', source, oldJob.onDuty, newJob.onDuty, after.job)
    end
    sendState(source, after)
    return true, nil
end

function Lifecycle.HandleJobChanged(source) return synchronizeJob(source, true, true) end
function Lifecycle.HandleDutyChanged(source) return synchronizeJob(source, false, true) end
function Lifecycle.IsCurrentSession(source, sessionId) return Cache.IsCurrentSession(tonumber(source), sessionId) end

function Lifecycle.AttachAdapter(adapter)
    if not adapter then return false, Errors.Create(Codes.FRAMEWORK_UNAVAILABLE, 'Cannot subscribe lifecycle without framework adapter') end
    local subscriptions = {
        { 'SubscribePlayerLoaded', function(source) Lifecycle.HandlePlayerLoaded(source) end },
        { 'SubscribePlayerUnloaded', function(source, reason) Lifecycle.HandlePlayerUnloaded(source, reason) end },
        { 'SubscribeJobChanged', function(source) Lifecycle.HandleJobChanged(source) end },
        { 'SubscribeDutyChanged', function(source) Lifecycle.HandleDutyChanged(source) end }
    }
    for _, spec in ipairs(subscriptions) do
        local callOk, ok, err = pcall(adapter[spec[1]], spec[2])
        if not callOk or ok ~= true then
            local structured = Errors.Is(err) and err or Errors.Create(Codes.ADAPTER_ERROR, 'Framework lifecycle subscription failed', {
                framework = adapter.metadata.name, method = spec[1]
            })
            return false, structured
        end
    end
    return true, nil
end

function Lifecycle.ReconstructPlayers()
    local adapter, frameworkErr = Framework.RequireHealthy(); if not adapter then return false, frameworkErr end
    local caps = adapter.metadata.capabilities
    if not (caps.player and caps.player.identity and caps.player.identity.character == true) then return true, 0 end
    local list = GetPlayers and GetPlayers() or {}
    local reconstructed = 0
    for _, rawSource in ipairs(list) do
        local source = tonumber(rawSource)
        local callOk, loaded = pcall(adapter.IsPlayerLoaded, source)
        if callOk and loaded then
            local ok = Lifecycle.HandlePlayerLoaded(source, { reconstructed = true, emit = false })
            if ok then reconstructed = reconstructed + 1 end
        end
    end
    if reconstructed > 0 then Logger.Info('Reconstructed normalized player cache', { players = reconstructed }, 'nexm_core') end
    return true, reconstructed
end

function Lifecycle.FrameworkUnavailable(err)
    Cache.ClearAll()
    if TriggerClientEvent then TriggerClientEvent('nexm_core:client:frameworkUnavailable', -1, err and Errors.Copy(err) or nil) end
end

function Lifecycle.InitializeGlobal()
    if globalInitialized then return end
    globalInitialized = true
    AddEventHandler('playerDropped', function(reason)
        Lifecycle.HandlePlayerUnloaded(tonumber(source), reason or 'playerDropped')
    end)

    -- Narrow resync channel for nexm_core client restart ordering. The client
    -- supplies no identity/job data; server cache remains authoritative.
    RegisterNetEvent('nexm_core:server:requestLocalState', function()
        local src = tonumber(source)
        local snapshot = src and Cache.Get(src) or nil
        if snapshot and Framework.IsHealthy() then sendState(src, snapshot) end
    end)
end

NEXM_INTERNAL.Modules.Lifecycle = Lifecycle
