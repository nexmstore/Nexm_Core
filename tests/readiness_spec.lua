local total, failed = 0, 0
local function expect(name, condition)
    total = total + 1
    if condition then print('[PASS] ' .. name) else failed = failed + 1; print('[FAIL] ' .. name) end
end

local Readiness = NEXM_INTERNAL.Modules.Readiness
local State = NEXM_INTERNAL.Modules.State
local States = NEXM_INTERNAL.Modules.Constants.STATES

local firedA, firedB = 0, 0
local ok = Readiness.Subscribe(function() firedA = firedA + 1 end, 'nexm_a')
expect('Readiness subscription accepted before READY', ok == true)
ok = Readiness.Subscribe(function() firedB = firedB + 1 end, 'nexm_b')
expect('Second readiness subscription accepted', ok == true)

local removed = Readiness.CleanupOwner('nexm_a')
expect('Readiness subscription cleanup by owner', removed == 1)

State.Set(States.DATABASE)
State.Set(States.MIGRATING)
State.Set(States.FRAMEWORK)
State.Set(States.PLATFORM)
State.Set(States.READY)
Readiness.MarkReady()
expect('Cleaned readiness callback does not fire', firedA == 0)
expect('Remaining readiness callback fires once', firedB == 1)

local immediate = 0
Readiness.Subscribe(function() immediate = immediate + 1 end, 'nexm_c')
expect('OnReady subscription after READY runs immediately', immediate == 1)

print(('Tests: %d, Failed: %d'):format(total, failed))
if failed > 0 then error(('Readiness tests failed: %d'):format(failed)) end
