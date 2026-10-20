local total, failed = 0, 0
local function expect(name, condition)
    total = total + 1
    if condition then print('[PASS] ' .. name) else failed = failed + 1; print('[FAIL] ' .. name) end
end

local Errors = NEXM_INTERNAL.Modules.Errors
local State = NEXM_INTERNAL.Modules.State
local States = NEXM_INTERNAL.Modules.Constants.STATES

TEST_INVOKER = 'nexm_justice'
local justice = GetCoreObject()

local _, err = justice.DB.Query('SELECT 1')
expect('Public DB refuses calls before READY', Errors.Is(err, 'CORE_NOT_READY'))

State.Set(States.DATABASE)
State.Set(States.MIGRATING)
State.Set(States.FRAMEWORK)
State.Set(States.PLATFORM)
State.Set(States.READY)

local ok
ok, err = justice.Resources.Register({ name = 'nexm_fake', version = '1.0.0', requiresCore = '>=1.0.0-0' })
expect('Facade owner cannot be spoofed by resource metadata', ok == false and Errors.Is(err, 'OWNER_MISMATCH'))

ok, err = justice.Resources.Register({ version = '1.0.0', requiresCore = '>=1.0.0-0' })
expect('Facade registers actual invoking resource', ok == true)

ok, err = justice.Services.Register('justice', { ping = function() return true end }, {
    version = '1.0.0', apiVersion = 1
})
expect('Resource-bound facade owns service registration', ok == true)

TEST_INVOKER = 'nexm_fake'
local fake = GetCoreObject()
ok, err = fake.Services.Register('justice', {}, { version = '1.0.0', apiVersion = 1 })
expect('Second facade cannot overwrite foreign service', ok == false and Errors.Is(err, 'REGISTRATION_CONFLICT'))

print(('Tests: %d, Failed: %d'):format(total, failed))
if failed > 0 then error(('Facade ownership tests failed: %d'):format(failed)) end
