local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local adapter = {
    metadata = {
        name = 'esx',
        resource = 'es_extended',
        version = nil,
        capabilities = {
            player = {
                identity = { character = true, account = true, license = true },
                job = true,
                duty = true
            },
            jobs = { multiple = false },
            money = { cash = true, bank = true },
            framework = { permissions = true }
        }
    }
}

local ESX = nil
local initialized = false
local generation = 0
local handlers = {}

local function unsupported(feature)
    return nil, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Framework capability is not supported', { feature = feature, framework = 'esx' })
end
local function notFound(source)
    return nil, Errors.Create(Codes.PLAYER_NOT_FOUND, 'Player was not found in ESX', { source = source })
end
local function player(source)
    if not ESX or not ESX.GetPlayerFromId then return nil end
    return ESX.GetPlayerFromId(tonumber(source))
end
local function subscribe(eventName, callback, mapper)
    local myGeneration = generation
    local token = AddEventHandler(eventName, function(...)
        if not initialized or generation ~= myGeneration then return end
        if mapper then mapper(callback, ...) else callback(...) end
    end)
    handlers[#handlers + 1] = token
    return true, token
end
local function clearHandlers()
    if RemoveEventHandler then
        for _, token in ipairs(handlers) do pcall(RemoveEventHandler, token) end
    end
    handlers = {}
end

function adapter.IsAvailable()
    return GetResourceState and GetResourceState('es_extended') == 'started'
end
function adapter.Initialize()
    if not adapter.IsAvailable() then
        return false, Errors.Create(Codes.FRAMEWORK_UNAVAILABLE, 'ESX resource is not started', { resource = 'es_extended' })
    end
    local ok, result = pcall(function() return exports['es_extended']:getSharedObject() end)
    if not ok or type(result) ~= 'table' then
        return false, Errors.Create(Codes.FRAMEWORK_INITIALIZATION_FAILED, 'Failed to acquire ESX shared object', { resource = 'es_extended' })
    end
    ESX = result
    generation = generation + 1
    initialized = true
    adapter.metadata.version = GetResourceMetadata and GetResourceMetadata('es_extended', 'version', 0) or adapter.metadata.version
    return true, nil
end
function adapter.Shutdown()
    initialized = false
    generation = generation + 1
    clearHandlers()
    ESX = nil
    return true, nil
end
function adapter.GetState() return initialized and 'HEALTHY' or 'UNAVAILABLE' end
function adapter.GetPlayer(source) return player(source) end
function adapter.IsPlayerLoaded(source)
    return ESX ~= nil and ESX.IsPlayerLoaded ~= nil and ESX.IsPlayerLoaded(tonumber(source)) == true
end
function adapter.GetCharacterIdentifier(source)
    local xPlayer = player(source); if not xPlayer then return notFound(source) end
    local value = xPlayer.getIdentifier and xPlayer.getIdentifier() or xPlayer.identifier
    if value == nil then return unsupported('player.identity.character') end
    return tostring(value), nil
end
function adapter.GetAccountIdentifier(source)
    local xPlayer = player(source); if not xPlayer then return notFound(source) end
    local value = xPlayer.license
    if value == nil then return unsupported('player.identity.account') end
    return tostring(value), nil
end
function adapter.GetLicense(source)
    local xPlayer = player(source); if not xPlayer then return notFound(source) end
    local value = GetPlayerIdentifierByType and GetPlayerIdentifierByType(tostring(source), 'license') or xPlayer.license
    value = value or xPlayer.license
    if value == nil then return unsupported('player.identity.license') end
    return tostring(value), nil
end
function adapter.GetCharacterName(source)
    local xPlayer = player(source); if not xPlayer then return notFound(source) end
    local value = xPlayer.getName and xPlayer.getName() or xPlayer.name
    return tostring(value or GetPlayerName(source) or 'Unknown'), nil
end
function adapter.GetJob(source)
    local xPlayer = player(source); if not xPlayer then return notFound(source) end
    local job = xPlayer.getJob and xPlayer.getJob() or xPlayer.job
    if type(job) ~= 'table' then return unsupported('player.job') end
    local grade = tonumber(job.grade)
    if not grade or grade % 1 ~= 0 then
        return nil, Errors.Create(Codes.ADAPTER_ERROR, 'ESX returned an invalid job grade', { source = source })
    end
    local onDuty = nil
    if type(job.onDuty) == 'boolean' then onDuty = job.onDuty end
    return {
        name = tostring(job.name or ''),
        label = tostring(job.label or job.name or ''),
        grade = grade,
        gradeName = tostring(job.grade_name or job.gradeName or ''),
        onDuty = onDuty
    }, nil
end
function adapter.SubscribePlayerLoaded(callback)
    return subscribe('esx:playerLoaded', callback, function(cb, source) cb(tonumber(source)) end)
end
function adapter.SubscribePlayerUnloaded(callback)
    return subscribe('esx:playerLogout', callback, function(cb, source) cb(tonumber(source), 'framework_logout') end)
end
function adapter.SubscribeJobChanged(callback)
    return subscribe('esx:setJob', callback, function(cb, source) cb(tonumber(source)) end)
end
function adapter.SubscribeDutyChanged(callback)
    return subscribe('esx:setJob', callback, function(cb, source, job, lastJob)
        local before, after = nil, nil
        if type(lastJob) == 'table' and type(lastJob.onDuty) == 'boolean' then before = lastJob.onDuty end
        if type(job) == 'table' and type(job.onDuty) == 'boolean' then after = job.onDuty end
        if before ~= after then cb(tonumber(source)) end
    end)
end


local accountMap = { cash = 'money', bank = 'bank' }
function adapter.GetMoney(source, account)
    local xPlayer = player(source); if not xPlayer then return notFound(source) end
    local mapped = accountMap[account]
    if not mapped then return nil, Errors.Create(Codes.UNSUPPORTED_ACCOUNT, 'ESX money account is unsupported', { account = account }) end
    local data = xPlayer.getAccount and xPlayer.getAccount(mapped) or nil
    local amount = data and tonumber(data.money) or nil
    if amount == nil then return nil, Errors.Create(Codes.UNSUPPORTED_ACCOUNT, 'ESX money account is unavailable', { account = account, mapped = mapped }) end
    return amount, nil
end
function adapter.AddMoney(source, account, amount, reason)
    local xPlayer = player(source); if not xPlayer then local _, err = notFound(source); return false, err end
    local mapped = accountMap[account]
    if not mapped then return false, Errors.Create(Codes.UNSUPPORTED_ACCOUNT, 'ESX money account is unsupported', { account = account }) end
    local before, err = adapter.GetMoney(source, account); if before == nil then return false, err end
    if not xPlayer.addAccountMoney then return false, Errors.Create(Codes.ADAPTER_ERROR, 'ESX addAccountMoney is unavailable', { account = account }) end
    local ok, raw = pcall(xPlayer.addAccountMoney, mapped, amount, reason)
    if not ok then return false, Errors.Create(Codes.ADAPTER_ERROR, 'ESX addAccountMoney failed', { account = account }) end
    local after, afterErr = adapter.GetMoney(source, account); if after == nil then return false, afterErr end
    if after ~= before + amount then return false, Errors.Create(Codes.ADAPTER_ERROR, 'ESX money addition could not be verified', { account = account, before = before, after = after, amount = amount }) end
    return true, nil
end
function adapter.RemoveMoney(source, account, amount, reason)
    local xPlayer = player(source); if not xPlayer then local _, err = notFound(source); return false, err end
    local mapped = accountMap[account]
    if not mapped then return false, Errors.Create(Codes.UNSUPPORTED_ACCOUNT, 'ESX money account is unsupported', { account = account }) end
    local before, err = adapter.GetMoney(source, account); if before == nil then return false, err end
    if before < amount then return false, Errors.Create(Codes.INSUFFICIENT_FUNDS, 'Insufficient funds', { account = account, balance = before, required = amount }) end
    if not xPlayer.removeAccountMoney then return false, Errors.Create(Codes.ADAPTER_ERROR, 'ESX removeAccountMoney is unavailable', { account = account }) end
    local ok = pcall(xPlayer.removeAccountMoney, mapped, amount, reason)
    if not ok then return false, Errors.Create(Codes.ADAPTER_ERROR, 'ESX removeAccountMoney failed', { account = account }) end
    local after, afterErr = adapter.GetMoney(source, account); if after == nil then return false, afterErr end
    if after ~= before - amount then return false, Errors.Create(Codes.ADAPTER_ERROR, 'ESX money removal could not be verified', { account = account, before = before, after = after, amount = amount }) end
    return true, nil
end

function adapter.HasFrameworkPermission(source, permission)
    local xPlayer = player(source); if not xPlayer then local _, e = notFound(source); return false, e end
    if type(permission) ~= 'string' or permission == '' then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Invalid ESX group name') end
    if type(xPlayer.getGroup) ~= 'function' then return false, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'ESX group permission API is unavailable', { feature = 'framework.permissions' }) end
    local ok, group = pcall(xPlayer.getGroup)
    if not ok then return false, Errors.Create(Codes.ADAPTER_ERROR, 'ESX group permission check failed') end
    return tostring(group) == permission, nil
end

NEXM_INTERNAL.Adapters.Framework.esx = adapter
