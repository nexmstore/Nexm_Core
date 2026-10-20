local root = arg[1] or '.'
local suites = {
    { name = 'phase2_spec', file = 'phase2_spec.lua' },
    { name = 'registry_spec', file = 'registry_spec.lua' },
    { name = 'readiness_spec', file = 'readiness_spec.lua' },
    { name = 'facade_ownership_spec', file = 'facade_ownership_spec.lua', api = true },
    { name = 'bootstrap_order_spec', file = 'bootstrap_order_spec.lua', bootstrap = true },
    { name = 'database_spec', file = 'database_spec.lua' }
}

local failedSuites = 0

local function installStubs()
    TEST_INVOKER = nil
    json = { encode = function() return '{}' end, decode = function() return {} end }
    local env = { resourceStates = { oxmysql = 'started', ox_inventory = 'started' }, commands = {}, events = {}, nextHandler = 0 }
    function GetCurrentResourceName() return 'nexm_core' end
    function GetInvokingResource() return TEST_INVOKER end
    function GetResourceState(name) return env.resourceStates[name] or 'missing' end
    function GetResourcePath(name) return '/resources/' .. tostring(name) end
    function GetResourceMetadata() return nil end
    function GetPlayers() return {} end
    function GetPlayerIdentifierByType() return nil end
    function GetPlayerName(src) return 'Player' .. tostring(src) end
    function RegisterCommand(name, cb) env.commands[name] = cb end
    function AddEventHandler(name, cb)
        env.nextHandler = env.nextHandler + 1
        env.events[name] = env.events[name] or {}
        env.events[name][env.nextHandler] = cb
        return env.nextHandler
    end
    function RemoveEventHandler(token)
        for _, group in pairs(env.events) do if group[token] then group[token] = nil return end end
    end
    function RegisterNetEvent(name, cb) if cb then return AddEventHandler(name, cb) end end
    function TriggerEvent(name, ...)
        local group = env.events[name] or {}
        for _, cb in pairs(group) do cb(...) end
    end
    function TriggerClientEvent() end
    function TriggerServerEvent() end
    function CreateThread(fn) fn() end
    function Wait() end
    source = 0

    local registeredExports = {}
    exports = setmetatable({}, {
        __call = function(_, name, fn) registeredExports[name] = fn end,
        __index = function(_, resource)
            return setmetatable({}, { __index = function(_, method)
                return function(_, ...)
                    if resource == 'ox_inventory' then
                        local f = ({ GetItemCount=function() return 0 end, AddItem=function() return true end, RemoveItem=function() return true end, CanCarryItem=function() return true end, GetInventoryItems=function() return {} end })[method]
                        if f then return f(...) end
                    end
                    error(('missing export %s:%s'):format(resource, method))
                end
            end })
        end
    })

    MySQL = {
        query = { await = function(sql) if sql and sql:find('SELECT `migration`', 1, true) then return {} end return {} end },
        single = { await = function() return nil end },
        scalar = { await = function() return 1 end },
        insert = { await = function() return 1 end },
        update = { await = function() return 1 end },
        transaction = { await = function() return true end }
    }
    return env
end

local function loadFoundation(includeApi)
    local env = installStubs()
    Config = nil; NEXM_INTERNAL = nil; GetCoreObject = nil; NEXM_TEST_BOOT_ORDER = nil; NEXM_CUSTOM_INVENTORY_ADAPTER=nil
    dofile(root .. '/config.lua')
    dofile(root .. '/shared/init.lua'); dofile(root .. '/shared/constants.lua'); dofile(root .. '/shared/errors.lua'); dofile(root .. '/shared/validation.lua'); dofile(root .. '/shared/transport.lua'); dofile(root .. '/shared/semver.lua'); dofile(root .. '/shared/identity.lua'); dofile(root .. '/shared/safe_data.lua'); dofile(root .. '/shared/locale.lua'); dofile(root .. '/shared/notify_contract.lua')
    dofile(root .. '/server/state.lua'); dofile(root .. '/server/logger.lua'); dofile(root .. '/server/ownership.lua'); dofile(root .. '/server/database.lua'); dofile(root .. '/server/migrations.lua'); dofile(root .. '/server/migrations/core.lua')
    dofile(root .. '/server/registry_base.lua'); dofile(root .. '/server/managers/resources.lua'); dofile(root .. '/server/managers/services.lua'); dofile(root .. '/server/managers/features.lua'); dofile(root .. '/server/managers/integrations.lua'); dofile(root .. '/server/readiness.lua')
    dofile(root .. '/server/framework_contract.lua'); dofile(root .. '/adapters/framework/esx.lua'); dofile(root .. '/adapters/framework/qbcore.lua'); dofile(root .. '/adapters/framework/qbox.lua'); dofile(root .. '/adapters/framework/standalone.lua'); dofile(root .. '/server/managers/framework.lua')
    dofile(root .. '/server/player_cache.lua'); dofile(root .. '/server/player.lua'); dofile(root .. '/server/jobs.lua'); dofile(root .. '/server/lifecycle.lua')
    dofile(root .. '/server/session_guard.lua'); dofile(root .. '/server/money.lua'); dofile(root .. '/server/inventory_contract.lua'); dofile(root .. '/custom/inventory.lua')
    dofile(root .. '/adapters/inventory/ox_inventory.lua'); dofile(root .. '/adapters/inventory/qb_inventory.lua'); dofile(root .. '/adapters/inventory/esx.lua'); dofile(root .. '/adapters/inventory/qs_inventory.lua'); dofile(root .. '/server/managers/inventory.lua'); dofile(root .. '/server/inventory.lua'); dofile(root .. '/custom/audit.lua'); dofile(root .. '/server/audit.lua'); dofile(root .. '/server/managers/notify.lua'); dofile(root .. '/server/notify.lua'); dofile(root .. '/server/components.lua'); dofile(root .. '/server/diagnostics.lua')
    if includeApi then dofile(root .. '/server/api.lua') end
    return env
end

for _, suite in ipairs(suites) do
    local env = loadFoundation(suite.api == true)
    if suite.bootstrap then
        Config.Framework = 'standalone'
        Config.FrameworkAutoStandalone = false
        NEXM_TEST_BOOT_ORDER = {}
        dofile(root .. '/server/bootstrap.lua')
    end
    local ok, err = pcall(dofile, root .. '/tests/' .. suite.file)
    if ok then
        print(('[SUITE PASS] %s'):format(suite.name))
    else
        failedSuites = failedSuites + 1
        print(('[SUITE FAIL] %s :: %s'):format(suite.name, tostring(err)))
    end
end

print(('PHASE2 REGRESSION SUITES: %d, FAILED SUITES: %d'):format(#suites, failedSuites))
if failedSuites > 0 then os.exit(1) end
