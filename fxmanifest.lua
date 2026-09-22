fx_version 'cerulean'
game 'gta5'

name 'nexm_core'
author 'NEXM'
description 'Reusable Foundation for the NEXM Script Ecosystem'
version '1.0.0-rc.1.hotfix.3'
nexm_build 'mvp_rc1_matrix_13401539'

dependency 'oxmysql'

-- Cross-resource client loaders (for @nexm_core/import.lua) must be present in
-- the nexm_core client packfile. Server-side @ imports can read the resource
-- filesystem directly; clients can only execute files delivered in the packfile.
files {
    'import.lua'
}

shared_scripts {
    'config.lua',
    'shared/init.lua',
    'shared/constants.lua',
    'shared/errors.lua',
    'shared/validation.lua',
    'shared/transport.lua',
    'shared/semver.lua',
    'shared/identity.lua',
    'shared/network_validation.lua',
    'shared/safe_data.lua',
    'shared/locale.lua',
    'shared/notify_contract.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/state.lua',
    'server/logger.lua',
    'server/ownership.lua',
    'server/database.lua',
    'server/migrations.lua',
    'server/migrations/core.lua',
    'server/registry_base.lua',
    'server/managers/resources.lua',
    'server/managers/services.lua',
    'server/managers/features.lua',
    'server/managers/integrations.lua',
    'server/readiness.lua',
    'server/framework_contract.lua',
    'adapters/framework/esx.lua',
    'adapters/framework/qbcore.lua',
    'adapters/framework/qbox.lua',
    'adapters/framework/standalone.lua',
    'server/managers/framework.lua',
    'server/player_cache.lua',
    'server/player.lua',
    'server/jobs.lua',
    'server/lifecycle.lua',
    'server/session_guard.lua',
    'server/money.lua',
    'server/inventory_contract.lua',
    'custom/inventory.lua',
    'adapters/inventory/ox_inventory.lua',
    'adapters/inventory/qb_inventory.lua',
    'adapters/inventory/esx.lua',
    'adapters/inventory/qs_inventory.lua',
    'server/managers/inventory.lua',
    'server/inventory.lua',
    'custom/audit.lua',
    'server/audit.lua',
    'server/rate_limit.lua',
    'server/event_bus.lua',
    'server/permissions.lua',
    'server/callbacks.lua',
    'server/managers/notify.lua',
    'server/notify.lua',
    'server/components.lua',
    'server/diagnostics.lua',
    'server/api.lua',
    'server/cleanup.lua',
    'server/bootstrap.lua'
}

client_scripts {
    'custom/notify.lua',
    'adapters/notify/nexm_notify.lua',
    'adapters/notify/ox_lib.lua',
    'adapters/notify/esx.lua',
    'adapters/notify/qbcore.lua',
    'adapters/notify/qbox.lua',
    'client/managers/notify.lua',
    'client/notify.lua',
    'client/state.lua',
    'client/events.lua',
    'client/callbacks.lua',
    'client/api.lua'
}

-- NEXM Core is intentionally distributed fully open-source.
-- Ignore every file from Cfx Asset Escrow encryption.
escrow_ignore {
    '*',
    '**/*'
}
