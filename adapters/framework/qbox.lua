local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local adapter = {
    metadata = {
        name = 'qbox', resource = 'qbx_core', version = nil,
        capabilities = {
            player = { identity = { character = true, account = true, license = true }, job = true, duty = true },
            jobs = { multiple = true },
            money = { cash = true, bank = true },
            framework = { permissions = true }
        }
    }
}
local initialized, generation = false, 0
local handlers = {}
local function notFound(source) return nil, Errors.Create(Codes.PLAYER_NOT_FOUND, 'Player was not found in Qbox', { source = source }) end
local function player(source)
    if not initialized then return nil end
    local ok, result = pcall(function() return exports['qbx_core']:GetPlayer(tonumber(source)) end)
    return ok and result or nil
end
local function subscribe(eventName, callback, mapper)
    local myGeneration = generation
    local token = AddEventHandler(eventName, function(...)
        if not initialized or generation ~= myGeneration then return end
        mapper(callback, ...)
    end)
    handlers[#handlers + 1] = token
    return true, token
end
local function clearHandlers()
    if RemoveEventHandler then for _, token in ipairs(handlers) do pcall(RemoveEventHandler, token) end end
    handlers = {}
end
function adapter.IsAvailable() return GetResourceState and GetResourceState('qbx_core') == 'started' end
function adapter.Initialize()
    if not adapter.IsAvailable() then return false, Errors.Create(Codes.FRAMEWORK_UNAVAILABLE, 'Qbox resource is not started', { resource = 'qbx_core' }) end
    local ok = pcall(function() return exports['qbx_core']:GetPlayer(-1) end)
    if not ok then return false, Errors.Create(Codes.FRAMEWORK_INITIALIZATION_FAILED, 'Qbox exports are unavailable', { resource = 'qbx_core' }) end
    generation = generation + 1; initialized = true
    adapter.metadata.version = GetResourceMetadata and GetResourceMetadata('qbx_core', 'version', 0) or adapter.metadata.version
    return true, nil
end
function adapter.Shutdown() initialized = false; generation = generation + 1; clearHandlers(); return true, nil end
function adapter.GetState() return initialized and 'HEALTHY' or 'UNAVAILABLE' end
function adapter.GetPlayer(source) return player(source) end
function adapter.IsPlayerLoaded(source) return player(source) ~= nil end
function adapter.GetCharacterIdentifier(source)
    local p = player(source); if not p then return notFound(source) end
    local d = p.PlayerData; if not d or not d.citizenid then return nil, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Qbox character identity is unavailable', { source = source }) end
    return tostring(d.citizenid), nil
end
function adapter.GetAccountIdentifier(source)
    local p = player(source); if not p then return notFound(source) end
    local value = p.PlayerData and p.PlayerData.userId
    if value == nil then return nil, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Qbox account identity is unavailable', { source = source }) end
    return tostring(value), nil
end
function adapter.GetLicense(source)
    local p = player(source); if not p then return notFound(source) end
    local value = GetPlayerIdentifierByType and GetPlayerIdentifierByType(tostring(source), 'license') or nil
    value = value or (p.PlayerData and p.PlayerData.license)
    if not value then return nil, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Qbox license identity is unavailable', { source = source }) end
    return tostring(value), nil
end
function adapter.GetCharacterName(source)
    local p = player(source); if not p then return notFound(source) end
    local c = p.PlayerData and p.PlayerData.charinfo or {}
    local name = ((c.firstname or '') .. ' ' .. (c.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then name = GetPlayerName(source) or 'Unknown' end
    return name, nil
end
function adapter.GetJob(source)
    local p = player(source); if not p then return notFound(source) end
    local job = p.PlayerData and p.PlayerData.job
    if type(job) ~= 'table' then return nil, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Qbox primary job is unavailable', { source = source }) end
    local grade = tonumber(type(job.grade) == 'table' and job.grade.level or job.grade)
    if not grade or grade % 1 ~= 0 then return nil, Errors.Create(Codes.ADAPTER_ERROR, 'Qbox returned an invalid job grade', { source = source }) end
    local onDuty = nil
    if type(job.onduty) == 'boolean' then onDuty = job.onduty end
    return { name = tostring(job.name or ''), label = tostring(job.label or job.name or ''), grade = grade,
        gradeName = tostring(type(job.grade) == 'table' and (job.grade.name or '') or ''), onDuty = onDuty }, nil
end
function adapter.SubscribePlayerLoaded(callback)
    return subscribe('QBCore:Server:OnPlayerLoaded', callback, function(cb) cb(tonumber(source)) end)
end
function adapter.SubscribePlayerUnloaded(callback)
    return subscribe('QBCore:Server:OnPlayerUnload', callback, function(cb, src) cb(tonumber(src or source), 'framework_unload') end)
end
function adapter.SubscribeJobChanged(callback)
    return subscribe('QBCore:Server:OnJobUpdate', callback, function(cb, src) cb(tonumber(src)) end)
end
function adapter.SubscribeDutyChanged(callback)
    return subscribe('QBCore:Server:SetDuty', callback, function(cb, src) cb(tonumber(src)) end)
end

function adapter.GetMoney(source, account)
    if account ~= 'cash' and account ~= 'bank' then return nil, Errors.Create(Codes.UNSUPPORTED_ACCOUNT, 'Qbox money account is unsupported', { account = account }) end
    local p = player(source); if not p then return notFound(source) end
    local ok, value = pcall(function() return exports['qbx_core']:GetMoney(source, account) end)
    if not ok then return nil, Errors.Create(Codes.ADAPTER_ERROR, 'Qbox GetMoney failed', { account = account }) end
    value = tonumber(value)
    if value == nil then return nil, Errors.Create(Codes.UNSUPPORTED_ACCOUNT, 'Qbox money account is unavailable', { account = account }) end
    return value, nil
end
function adapter.AddMoney(source, account, amount, reason)
    if account ~= 'cash' and account ~= 'bank' then return false, Errors.Create(Codes.UNSUPPORTED_ACCOUNT, 'Qbox money account is unsupported', { account = account }) end
    if not player(source) then local _,e=notFound(source); return false,e end
    local before, err = adapter.GetMoney(source, account); if before == nil then return false, err end
    local ok, result = pcall(function() return exports['qbx_core']:AddMoney(source, account, amount, reason) end)
    if not ok or result ~= true then return false, Errors.Create(Codes.ADAPTER_ERROR, 'Qbox AddMoney reported failure', { account = account }) end
    local after, afterErr = adapter.GetMoney(source, account); if after == nil then return false, afterErr end
    if after ~= before + amount then return false, Errors.Create(Codes.ADAPTER_ERROR, 'Qbox money addition could not be verified', { account = account, before = before, after = after, amount = amount }) end
    return true, nil
end
function adapter.RemoveMoney(source, account, amount, reason)
    if account ~= 'cash' and account ~= 'bank' then return false, Errors.Create(Codes.UNSUPPORTED_ACCOUNT, 'Qbox money account is unsupported', { account = account }) end
    if not player(source) then local _,e=notFound(source); return false,e end
    local before, err = adapter.GetMoney(source, account); if before == nil then return false, err end
    if before < amount then return false, Errors.Create(Codes.INSUFFICIENT_FUNDS, 'Insufficient funds', { account = account, balance = before, required = amount }) end
    local ok, result = pcall(function() return exports['qbx_core']:RemoveMoney(source, account, amount, reason) end)
    if not ok or result ~= true then return false, Errors.Create(Codes.ADAPTER_ERROR, 'Qbox RemoveMoney reported failure', { account = account }) end
    local after, afterErr = adapter.GetMoney(source, account); if after == nil then return false, afterErr end
    if after ~= before - amount then return false, Errors.Create(Codes.ADAPTER_ERROR, 'Qbox money removal could not be verified', { account = account, before = before, after = after, amount = amount }) end
    return true, nil
end

function adapter.HasFrameworkPermission(source, permission)
    local p = player(source); if not p then local _, e = notFound(source); return false, e end
    if type(permission) ~= 'string' or permission == '' then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'Invalid Qbox permission name') end
    if not IsPlayerAceAllowed then return false, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Qbox ACE permission API is unavailable', { feature = 'framework.permissions' }) end
    local ok, allowed = pcall(IsPlayerAceAllowed, source, permission)
    if not ok then return false, Errors.Create(Codes.ADAPTER_ERROR, 'Qbox permission check failed') end
    return allowed == true, nil
end

NEXM_INTERNAL.Adapters.Framework.qbox = adapter
