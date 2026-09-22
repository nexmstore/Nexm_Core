local Constants = NEXM_INTERNAL.Modules.Constants
local State = NEXM_INTERNAL.Modules.State
local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local Logger = NEXM_INTERNAL.Modules.Logger
local DB = NEXM_INTERNAL.Modules.InternalDB or NEXM_INTERNAL.Modules.DB
local Migrations = NEXM_INTERNAL.Modules.Migrations
local Framework = NEXM_INTERNAL.Managers.Framework
local Lifecycle = NEXM_INTERNAL.Modules.Lifecycle
local InventoryManager = NEXM_INTERNAL.Managers.Inventory
local NotifyManager = NEXM_INTERNAL.Managers.Notify
local Audit = NEXM_INTERNAL.Modules.Audit
local Diagnostics = NEXM_INTERNAL.Modules.Diagnostics
local Readiness = NEXM_INTERNAL.Modules.Readiness
local Codes, States, Health = Constants.ERROR_CODES, Constants.STATES, Constants.HEALTH

local function testOrder(value)
    if NEXM_TEST_BOOT_ORDER then NEXM_TEST_BOOT_ORDER[#NEXM_TEST_BOOT_ORDER + 1] = value end
end
local function fail(err)
    local structured = Errors.Is(err) and err or Errors.Create(Codes.INVALID_ARGUMENT, 'Unknown bootstrap failure')
    State.Fail(structured)
    Logger.Error('NEXM Core bootstrap failed', { error = structured }, 'nexm_core')
    Diagnostics.Initialize()
end
local function validatePriority(list, name)
    local ok, err = Validation.Table(list, { name = name, maxEntries = 16 })
    if not ok then return false, err end
    for index, value in ipairs(list) do
        ok, err = Validation.String(value, {
            name = ('%s[%d]'):format(name, index), nonEmpty = true, min = 1, max = 32,
            allowed = { 'esx', 'qbcore', 'qbox' }
        })
        if not ok then return false, err end
    end
    return true, nil
end
local function validateConfig()
    local ok, err = Validation.Boolean(Config.Debug, { name = 'Config.Debug' }); if not ok then return false, err end
    ok, err = Validation.String(Config.Framework, {
        name = 'Config.Framework', nonEmpty = true,
        allowed = { 'auto', 'esx', 'qbcore', 'qbox', 'standalone' }
    }); if not ok then return false, err end
    ok, err = Validation.Boolean(Config.FrameworkAutoStandalone, { name = 'Config.FrameworkAutoStandalone' }); if not ok then return false, err end
    ok, err = validatePriority(Config.FrameworkPriority or {}, 'Config.FrameworkPriority'); if not ok then return false, err end
    ok, err = Validation.String(Config.Inventory, { name = 'Config.Inventory', nonEmpty = true, allowed = { 'auto', 'none', 'ox_inventory', 'qb-inventory', 'esx', 'qs-inventory', 'custom' } }); if not ok then return false, err end
    ok, err = Validation.String(Config.Notify, { name = 'Config.Notify', nonEmpty = true, allowed = { 'auto', 'none', 'nexm_notify', 'ox_lib', 'esx', 'qbcore', 'qbox', 'custom' } }); if not ok then return false, err end
    ok, err = Validation.Boolean(Config.NotifyFallback, { name = 'Config.NotifyFallback' }); if not ok then return false, err end
    ok, err = Validation.Table(Config.NotifyPriority or {}, { name = 'Config.NotifyPriority', maxEntries = 16 }); if not ok then return false, err end
    for index, value in ipairs(Config.NotifyPriority or {}) do
        ok, err = Validation.String(value, { name = ('Config.NotifyPriority[%d]'):format(index), nonEmpty = true, allowed = { 'nexm_notify', 'ox_lib', 'framework', 'esx', 'qbcore', 'qbox', 'custom' } })
        if not ok then return false, err end
    end
    ok, err = Validation.String(Config.Logging.level or Config.Logging.Level, { name = 'Config.Logging.level', nonEmpty = true, allowed = { 'debug', 'info', 'warn', 'error' } }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Logging.repeatedErrorWindowMs, { name = 'Config.Logging.repeatedErrorWindowMs', min = 0, max = 3600000 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Logging.maxMetadataLength, { name = 'Config.Logging.maxMetadataLength', min = 128, max = 65536 }); if not ok then return false, err end
    ok, err = Validation.String(Config.Locale, { name = 'Config.Locale', nonEmpty = true, min = 2, max = 16, pattern = '^[%a][%w_%-]*$' }); if not ok then return false, err end
    ok, err = Validation.String(Config.LocaleFallback, { name = 'Config.LocaleFallback', nonEmpty = true, min = 2, max = 16, pattern = '^[%a][%w_%-]*$' }); if not ok then return false, err end
    ok, err = Validation.Boolean(Config.NotifyCustomEnabled, { name = 'Config.NotifyCustomEnabled' }); if not ok then return false, err end
    ok, err = Validation.Table(Config.NotifyDefaults, { name = 'Config.NotifyDefaults', maxEntries = 16 }); if not ok then return false, err end
    ok, err = Validation.String(Config.NotifyDefaults.type, { name = 'Config.NotifyDefaults.type', nonEmpty = true, allowed = { 'info', 'success', 'warning', 'error' } }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.NotifyDefaults.duration, { name = 'Config.NotifyDefaults.duration', min = 500, max = 60000 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.NotifyDefaults.minDuration, { name = 'Config.NotifyDefaults.minDuration', min = 100, max = 60000 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.NotifyDefaults.maxDuration, { name = 'Config.NotifyDefaults.maxDuration', min = Config.NotifyDefaults.minDuration, max = 300000 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.NotifyDefaults.maxMessageLength, { name = 'Config.NotifyDefaults.maxMessageLength', min = 64, max = 16384 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.NotifyDefaults.maxTitleLength, { name = 'Config.NotifyDefaults.maxTitleLength', min = 16, max = 1024 }); if not ok then return false, err end
    ok, err = Validation.Table(Config.Integrations.priorities, { name = 'Config.Integrations.priorities', maxEntries = 64 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Security.MaxMoneyTransaction, { name = 'Config.Security.MaxMoneyTransaction', min = 1, max = 2147483647 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Security.MaxItemTransaction, { name = 'Config.Security.MaxItemTransaction', min = 1, max = 1000000 }); if not ok then return false, err end
    local invPriority = Config.Integrations.priorities.inventory or {}
    ok, err = Validation.Table(invPriority, { name = 'Config.Integrations.priorities.inventory', maxEntries = 16 }); if not ok then return false, err end
    for index, value in ipairs(invPriority) do
        ok, err = Validation.String(value, { name = ('Config.Integrations.priorities.inventory[%d]'):format(index), nonEmpty = true, allowed = { 'ox_inventory', 'qb-inventory', 'esx', 'qs-inventory', 'custom' } })
        if not ok then return false, err end
    end
    local notifyPriority = Config.Integrations.priorities.notify or {}
    ok, err = Validation.Table(notifyPriority, { name = 'Config.Integrations.priorities.notify', maxEntries = 16 }); if not ok then return false, err end
    for index, value in ipairs(notifyPriority) do
        ok, err = Validation.String(value, { name = ('Config.Integrations.priorities.notify[%d]'):format(index), nonEmpty = true, allowed = { 'nexm_notify', 'ox_lib', 'framework', 'esx', 'qbcore', 'qbox', 'custom' } })
        if not ok then return false, err end
    end
    ok, err = Validation.String(Config.Database.healthQuery, { name = 'Config.Database.healthQuery', nonEmpty = true, max = 1024 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Callback.Timeout, { name = 'Config.Callback.Timeout', min = 250, max = 60000 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Callback.MinTimeout, { name = 'Config.Callback.MinTimeout', min = 50, max = Config.Callback.Timeout }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Callback.MaxTimeout, { name = 'Config.Callback.MaxTimeout', min = Config.Callback.Timeout, max = 300000 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Callback.maxNameLength, { name = 'Config.Callback.maxNameLength', min = 8, max = 256 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Callback.maxRequestIdLength, { name = 'Config.Callback.maxRequestIdLength', min = 8, max = 256 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Callback.DefaultRateLimit.limit, { name = 'Config.Callback.DefaultRateLimit.limit', min = 1, max = 100000 }); if not ok then return false, err end
    ok, err = Validation.Number(Config.Callback.DefaultRateLimit.window, { name = 'Config.Callback.DefaultRateLimit.window', min = 0.05, max = 3600 }); if not ok then return false, err end
    for _, direction in ipairs({ 'request', 'response' }) do
        local limits = Config.Network[direction]
        ok, err = Validation.Table(limits, { name = 'Config.Network.' .. direction, maxEntries = 16 }); if not ok then return false, err end
        for _, field in ipairs({ 'maxDepth', 'maxEntries', 'maxStringLength', 'maxTotalNodes', 'maxKeyLength' }) do
            ok, err = Validation.Integer(limits[field], { name = ('Config.Network.%s.%s'):format(direction, field), min = 1, max = 1000000 }); if not ok then return false, err end
        end
    end
    ok, err = Validation.Integer(Config.Security.RPCGlobalLimit.limit, { name = 'Config.Security.RPCGlobalLimit.limit', min = 1, max = 100000 }); if not ok then return false, err end
    ok, err = Validation.Number(Config.Security.RPCGlobalLimit.window, { name = 'Config.Security.RPCGlobalLimit.window', min = 0.05, max = 3600 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Security.maxStringLength, { name = 'Config.Security.maxStringLength', min = 64, max = 1048576 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Security.maxIdentifierLength, { name = 'Config.Security.maxIdentifierLength', min = 16, max = 4096 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Security.maxTableDepth, { name = 'Config.Security.maxTableDepth', min = 1, max = 64 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Security.maxTableEntries, { name = 'Config.Security.maxTableEntries', min = 16, max = 100000 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Security.maxTransactionReasonLength, { name = 'Config.Security.maxTransactionReasonLength', min = 8, max = 2048 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Security.maxItemNameLength, { name = 'Config.Security.maxItemNameLength', min = 8, max = 1024 }); if not ok then return false, err end
    ok, err = Validation.Boolean(Config.Audit.Enabled, { name = 'Config.Audit.Enabled' }); if not ok then return false, err end
    ok, err = Validation.Table(Config.Audit.Backends, { name = 'Config.Audit.Backends', maxEntries = 8 }); if not ok then return false, err end
    for _, backend in ipairs({ 'console', 'database', 'discord', 'custom' }) do
        ok, err = Validation.Boolean(Config.Audit.Backends[backend], { name = 'Config.Audit.Backends.' .. backend }); if not ok then return false, err end
    end
    ok, err = Validation.String(Config.Audit.DiscordWebhook, { name = 'Config.Audit.DiscordWebhook', max = 4096 }); if not ok then return false, err end
    ok, err = Validation.Boolean(Config.Audit.DiscordIncludeIdentifiers, { name = 'Config.Audit.DiscordIncludeIdentifiers' }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Audit.RetentionDays, { name = 'Config.Audit.RetentionDays', min = 0, max = 36500 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Audit.Queue.maxSize, { name = 'Config.Audit.Queue.maxSize', min = 1, max = 10000 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Audit.Queue.batchSize, { name = 'Config.Audit.Queue.batchSize', min = 1, max = Config.Audit.Queue.maxSize }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Audit.Queue.retryLimit, { name = 'Config.Audit.Queue.retryLimit', min = 0, max = 10 }); if not ok then return false, err end
    ok, err = Validation.Integer(Config.Audit.Queue.retryBackoffMs, { name = 'Config.Audit.Queue.retryBackoffMs', min = 0, max = 3600000 }); if not ok then return false, err end
    ok, err = Validation.String(Config.Audit.Queue.dropPolicy, { name = 'Config.Audit.Queue.dropPolicy', nonEmpty = true, allowed = { 'oldest', 'newest' } }); if not ok then return false, err end
    return true, nil
end

CreateThread(function()
    print(('[NEXM] build=%s'):format(tostring(Constants.BUILD_ID or 'unknown')))
    Logger.Info('Bootstrapping NEXM Core', { version = Constants.VERSION, buildId = Constants.BUILD_ID }, 'nexm_core')
    local configOk, configErr = validateConfig(); if not configOk then fail(configErr); return end

    local stateOk, stateErr = State.Set(States.DATABASE); testOrder('STATE:DATABASE')
    if not stateOk then fail(stateErr); return end
    local dbOk, dbErr = DB.Connect(); testOrder('DB_CONNECT')
    if not dbOk then fail(dbErr); return end

    stateOk, stateErr = State.Set(States.MIGRATING); testOrder('STATE:MIGRATING')
    if not stateOk then fail(stateErr); return end
    local migrationTableOk, migrationTableErr = Migrations.Bootstrap(); testOrder('MIGRATION_TABLE')
    if not migrationTableOk then fail(migrationTableErr); return end
    local coreMigrationsOk, coreMigrationsErr = Migrations.RunCore(); testOrder('CORE_MIGRATIONS')
    if not coreMigrationsOk then fail(coreMigrationsErr); return end

    Framework.RegisterBuiltinAdapters(); testOrder('ADAPTER_REGISTRY')
    stateOk, stateErr = State.Set(States.FRAMEWORK); testOrder('STATE:FRAMEWORK')
    if not stateOk then fail(stateErr); return end
    local frameworkOk, frameworkErr = Framework.InitializeSelected(); testOrder('FRAMEWORK_INIT')
    if not frameworkOk then fail(frameworkErr); return end

    stateOk, stateErr = State.Set(States.PLATFORM); testOrder('STATE:PLATFORM')
    if not stateOk then fail(stateErr); return end

    Lifecycle.InitializeGlobal()
    local attachOk, attachErr = Lifecycle.AttachAdapter(Framework.GetSelected()); testOrder('LIFECYCLE_SUBSCRIBE')
    if not attachOk then fail(attachErr); return end
    local reconstructOk, reconstructErr = Lifecycle.ReconstructPlayers(); testOrder('PLAYER_CACHE_RECONSTRUCT')
    if not reconstructOk then fail(reconstructErr); return end
    Framework.InstallResourceMonitoring()

    local inventoryOk, inventoryErr = InventoryManager.InitializeSelected(); testOrder('INVENTORY_INIT')
    if not inventoryOk then
        -- Inventory is an optional Core component. Selection/initialization errors
        -- are preserved in component diagnostics and product requirement checks,
        -- but do not globally prevent NEXM Core READY.
        Logger.Warn('Inventory component is not usable; Core will continue READY', { error = inventoryErr and inventoryErr.code }, 'nexm_core')
    end
    InventoryManager.InstallResourceMonitoring()

    local notifyOk, notifyErr = NotifyManager.InitializeSelected(); testOrder('NOTIFY_INIT')
    if not notifyOk and notifyErr and notifyErr.code ~= Codes.NOTIFY_DISABLED then
        Logger.Warn('Notify component is not usable; Core will continue READY', { error = notifyErr.code, component = 'notify' }, 'nexm_core')
    end
    NotifyManager.InstallResourceMonitoring()

    State.SetComponent('rpc', Health.HEALTHY, { direction = 'client-server-client' })
    local auditOk, auditErr = Audit.Initialize(); testOrder('AUDIT_INIT')
    if not auditOk then Logger.Warn('Audit initialization failed; gameplay remains unaffected', { error = auditErr and auditErr.code, component = 'audit' }, 'nexm_core') end

    Diagnostics.Initialize(); testOrder('DIAGNOSTICS')
    stateOk, stateErr = State.Set(States.READY); testOrder('STATE:READY')
    if not stateOk then fail(stateErr); return end

    Logger.Info('NEXM Core is READY', { framework = Framework.GetName() }, 'nexm_core')
    Readiness.MarkReady(); testOrder('READY_EVENT')
end)
