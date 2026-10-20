local total, failed = 0, 0

local function expect(name, condition)
    total = total + 1
    if not condition then
        failed = failed + 1
        print('[FAIL] ' .. name)
    else
        print('[PASS] ' .. name)
    end
end

-- Pure module tests assume shared/init.lua, constants.lua, errors.lua,
-- validation.lua and semver.lua have been loaded first.
local SemVer = NEXM_INTERNAL.Modules.SemVer
local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors

local cmp = SemVer.Compare('1.0.0', '1.0.1')
expect('SemVer Compare lower', cmp == -1)
cmp = SemVer.Compare('1.0.0-alpha', '1.0.0')
expect('SemVer prerelease lower than release', cmp == -1)
cmp = SemVer.Compare('2.0.0', '1.9.9')
expect('SemVer Compare higher', cmp == 1)

local ok = SemVer.Satisfies('1.5.0', '>=1.3.0 <2.0.0')
expect('SemVer AND range', ok == true)
ok = SemVer.Satisfies('2.0.0', '>=1.3.0 <2.0.0')
expect('SemVer upper bound', ok == false)
ok = SemVer.Satisfies('1.2.9', '~1.2.3')
expect('SemVer tilde', ok == true)
ok = SemVer.Satisfies('1.3.0', '~1.2.3')
expect('SemVer tilde rejects next minor', ok == false)
ok = SemVer.Satisfies('0.2.9', '^0.2.3')
expect('SemVer caret 0.x', ok == true)
ok = SemVer.Satisfies('0.3.0', '^0.2.3')
expect('SemVer caret 0.x upper bound', ok == false)
ok = SemVer.Satisfies('2.1.0', '^1.0.0 || >=2.0.0 <3.0.0')
expect('SemVer OR range', ok == true)


ok = SemVer.Satisfies('1.4.0', '>= 1.3.0 < 2.0.0')
expect('SemVer spaced comparators', ok == true)
cmp = SemVer.Compare('1.0.0-beta.11', '1.0.0-rc.1')
expect('SemVer prerelease lexical precedence', cmp == -1)
local invalidVersion, invalidErr = SemVer.Compare('1..0.0', '1.0.0')
expect('SemVer rejects empty core identifiers', invalidVersion == nil and Errors.Is(invalidErr, 'INVALID_VERSION'))
local pipeOk, pipeErr = SemVer.Satisfies('1.0.0', '1.0.0 | 2.0.0')
expect('SemVer rejects single-pipe OR', pipeOk == false and Errors.Is(pipeErr, 'INVALID_VERSION'))

local valid, err = Validation.Number(10, { min = 1, max = 20 })
expect('Validation Number valid', valid == true and err == nil)
valid, err = Validation.Number(0 / 0)
expect('Validation rejects NaN', valid == false and Errors.Is(err, 'INVALID_ARGUMENT'))
valid, err = Validation.Integer(1.5)
expect('Validation rejects non-integer', valid == false)
valid, err = Validation.Identifier('qbox:ABC_123')
expect('Validation Identifier valid', valid == true)
valid, err = Validation.Identifier('bad id with spaces')
expect('Validation Identifier rejects spaces', valid == false)
valid, err = Validation.Coordinates({ x = 1.0, y = 2.0, z = 3.0 })
expect('Validation Coordinates valid', valid == true)

print(('Tests: %d, Failed: %d'):format(total, failed))
if failed > 0 then
    error(('Phase 2 pure tests failed: %d'):format(failed))
end
