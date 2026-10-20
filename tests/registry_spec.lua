local total, failed = 0, 0
local function expect(name, condition)
    total = total + 1
    if condition then
        print('[PASS] ' .. name)
    else
        failed = failed + 1
        print('[FAIL] ' .. name)
    end
end

local State = NEXM_INTERNAL.Modules.State
local States = NEXM_INTERNAL.Modules.Constants.STATES
local Services = NEXM_INTERNAL.Managers.Services
local Features = NEXM_INTERNAL.Managers.Features
local Integrations = NEXM_INTERNAL.Managers.Integrations
local Resources = NEXM_INTERNAL.Managers.Resources
local Migrations = NEXM_INTERNAL.Modules.Migrations
local DB = NEXM_INTERNAL.Modules.DB
local Errors = NEXM_INTERNAL.Modules.Errors

local ok, err = Services.Register('justice', { ping = function() return true end }, {
    version = '1.0.0', apiVersion = 1
}, 'nexm_justice')
expect('Service first registration succeeds', ok == true and err == nil)

ok, err = Services.Register('justice', {}, { version = '1.0.0', apiVersion = 1 }, 'nexm_fake')
expect('Service cross-owner collision rejected', ok == false and Errors.Is(err, 'REGISTRATION_CONFLICT'))

ok, err = Features.Register('justice.advanced_gps', true, {}, 'nexm_justice')
expect('Feature first registration succeeds', ok == true)
ok, err = Features.Register('justice.advanced_gps', true, {}, 'nexm_fake')
expect('Feature cross-owner collision rejected', ok == false and Errors.Is(err, 'REGISTRATION_CONFLICT'))

ok, err = Resources.Register({ name = 'spoofed_name', version = '1.0.0', requiresCore = '>=1.0.0' }, 'nexm_justice')
expect('Resource owner spoof rejected', ok == false and Errors.Is(err, 'OWNER_MISMATCH'))

ok, err = Resources.Register({ version = '1.0.0', requiresCore = '>=2.0.0' }, 'nexm_future')
expect('Incompatible Core version rejected', ok == false and Errors.Is(err, 'INCOMPATIBLE_CORE_VERSION'))

ok, err = Integrations.RegisterInternal({
    category = 'inventory', name = 'ox_inventory', version = '1.0.0', critical = true, state = 'AVAILABLE', adapter = {}
}, 'nexm_core')
expect('First inventory integration registered', ok == true)

ok, err = Integrations.RegisterInternal({
    category = 'inventory', name = 'qb-inventory', version = '1.0.0', critical = true, state = 'AVAILABLE', adapter = {}
}, 'nexm_core')
expect('Second inventory integration registered', ok == true)

ok, err = Integrations.Select('inventory', 'auto', {})
expect('Ambiguous inventory auto-detection fails closed', ok == false and Errors.Is(err, 'AMBIGUOUS_INVENTORY_INTEGRATION'))

local selected
ok, selected = Integrations.Select('inventory', 'auto', { 'ox_inventory', 'qb-inventory' })
expect('Explicit priority resolves inventory ambiguity', ok == true and selected == 'ox_inventory')

ok, err = Integrations.Select('inventory', 'qb-inventory', {})
expect('Sticky inventory selection blocks hot switch', ok == false and Errors.Is(err, 'INTEGRATION_SELECTION_LOCKED'))

local caps = Integrations.GetCapabilities('inventory', 'ox_inventory')
if caps then caps.mutated = true end
local capsAgain = Integrations.GetCapabilities('inventory', 'ox_inventory')
expect('Integration capability metadata is returned as snapshot', not capsAgain or capsAgain.mutated == nil)

Integrations.CleanupOwner('nexm_core')
ok, err = Integrations.Select('inventory', 'auto', { 'qb-inventory' })
expect('Sticky selection does not hot-failover after owner cleanup', ok == false and Errors.Is(err, 'INTEGRATION_UNAVAILABLE'))

ok, err = Migrations.Register('nexm_test', {
    id = '001_initial',
    statements = { 'CREATE TABLE test_table (id INT)' }
}, 'nexm_test')
expect('Migration registration succeeds', ok == true)

local registered = Migrations.GetRegistered('nexm_test')
local checksum = registered['001_initial'] and registered['001_initial'].checksum
expect('Migration checksum generated', type(checksum) == 'string' and #checksum > 0)

local originalQuery = DB.Query
DB.Query = function(sql, params, owner)
    if sql:find('SELECT `migration`, `checksum`', 1, true) then
        return { { migration = '001_initial', checksum = 'adler32:deadbeef' } }, nil
    end
    return originalQuery(sql, params, owner)
end
ok, err = Migrations.Run('nexm_test')
expect('Migration checksum mismatch blocks rerun', ok == false and Errors.Is(err, 'MIGRATION_CHECKSUM_MISMATCH'))
DB.Query = originalQuery

ok, err = State.Set(States.DATABASE)
expect('State BOOTING -> DATABASE', ok == true)
ok, err = State.Set(States.READY)
expect('Invalid state jump rejected', ok == false and Errors.Is(err, 'INVALID_STATE_TRANSITION'))
ok = State.Set(States.MIGRATING)
expect('State DATABASE -> MIGRATING', ok == true)
ok = State.Set(States.FRAMEWORK)
expect('State MIGRATING -> FRAMEWORK', ok == true)
ok = State.Set(States.PLATFORM)
expect('State FRAMEWORK -> PLATFORM', ok == true)
ok = State.Set(States.READY)
expect('State PLATFORM -> READY', ok == true)

local removed = Services.CleanupOwner('nexm_justice')
expect('Owned service cleanup removes registration', removed == 1 and Services.Has('justice') == false)

print(('Tests: %d, Failed: %d'):format(total, failed))
if failed > 0 then error(('Registry tests failed: %d'):format(failed)) end
