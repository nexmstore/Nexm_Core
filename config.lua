Config = Config or {}

Config.Framework = 'auto'
-- Auto mode fails closed when no supported framework is active unless this is
-- explicitly enabled. Selecting Config.Framework = 'standalone' is preferred.
Config.FrameworkAutoStandalone = false
-- Empty by default: multiple active frameworks are ambiguous and fail closed.
-- Administrators may explicitly order supported names: qbox, qbcore, esx.
Config.FrameworkPriority = {}

Config.Inventory = 'auto'
-- Set to 'none' to intentionally disable inventory without blocking Core READY.
-- Empty by default: multiple active inventory backends are ambiguous and fail closed.
-- Supported names: ox_inventory, qb-inventory, esx, qs-inventory, custom.
Config.Notify = 'nexm_notify'
Config.NotifyFallback = true
Config.NotifyPriority = { 'nexm_notify', 'ox_lib', 'framework' }
Config.NotifyCustomEnabled = false
Config.NotifyDefaults = {
    type = 'info',
    duration = 5000,
    minDuration = 500,
    maxDuration = 60000,
    maxMessageLength = 2048,
    maxTitleLength = 128
}

Config.Locale = 'en'
Config.LocaleFallback = 'en'
Config.Debug = false

Config.Database = {
    healthQuery = 'SELECT 1'
}

Config.Logging = {
    level = 'info',
    repeatedErrorWindowMs = 10000,
    maxMetadataLength = 2000
}

Config.Integrations = {
    priorities = {
        inventory = {},
        notify = {}
    }
}

Config.Callback = {
    Timeout = 10000,
    MinTimeout = 250,
    MaxTimeout = 60000,
    maxNameLength = 64,
    maxRequestIdLength = 64,
    DefaultRateLimit = { limit = 20, window = 10 }
}

Config.Network = {
    request = { maxDepth = 8, maxEntries = 128, maxStringLength = 2048, maxTotalNodes = 512, maxKeyLength = 128 },
    response = { maxDepth = 8, maxEntries = 128, maxStringLength = 4096, maxTotalNodes = 512, maxKeyLength = 128 }
}

Config.Security = {
    maxStringLength = 4096,
    maxIdentifierLength = 256,
    maxTableDepth = 12,
    maxTableEntries = 2048,
    MaxMoneyTransaction = 10000000,
    MaxItemTransaction = 1000,
    maxTransactionReasonLength = 128,
    maxItemNameLength = 128,
    RPCGlobalLimit = { limit = 60, window = 10 }
}


Config.Audit = {
    Enabled = true,
    Backends = {
        console = false,
        database = true,
        discord = false,
        custom = false
    },
    DiscordWebhook = '',
    DiscordIncludeIdentifiers = false,
    RetentionDays = 0, -- 0 = automatic retention disabled
    MaxActionLength = 128,
    MaxSubjectLength = 256,
    MaxDataDepth = 8,
    MaxDataEntries = 256,
    MaxDataNodes = 768,
    MaxDataStringLength = 4096,
    Queue = {
        maxSize = 256,
        batchSize = 16,
        retryLimit = 2,
        retryBackoffMs = 1000,
        dropPolicy = 'oldest'
    }
}
