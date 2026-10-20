local total, failed = 0, 0
local function expect(name, condition)
    total = total + 1
    if condition then print('[PASS] ' .. name) else failed = failed + 1; print('[FAIL] ' .. name) end
end

local DB = NEXM_INTERNAL.Modules.DB
local Errors = NEXM_INTERNAL.Modules.Errors

local originalResourceState = GetResourceState
GetResourceState = function(name)
    if name == 'oxmysql' then return 'missing' end
    return originalResourceState(name)
end
local ok, err = DB.Connect()
expect('DB.Connect fails when oxmysql is unavailable', ok == false and Errors.Is(err, 'DATABASE_UNAVAILABLE'))
GetResourceState = originalResourceState

local originalQuery = MySQL.query.await
MySQL.query.await = function() error('synthetic database failure') end
local result
result, err = DB.Query('SELECT 1', {}, 'nexm_test')
expect('DB.Query normalizes thrown driver errors', result == nil and Errors.Is(err, 'DATABASE_ERROR'))
MySQL.query.await = originalQuery

local originalInsert = MySQL.insert.await
MySQL.insert.await = function() return 42 end
result, err = DB.Insert('INSERT INTO test (id) VALUES (?)', { 42 }, 'nexm_test')
expect('DB.Insert passes successful result through', result == 42 and err == nil)
MySQL.insert.await = originalInsert

local originalTransaction = MySQL.transaction.await
MySQL.transaction.await = function() return false end
ok, err = DB.Transaction({ { query = 'SELECT 1', values = {} } }, nil, 'nexm_test')
expect('DB.Transaction normalizes false transaction result', ok == false and Errors.Is(err, 'DATABASE_ERROR'))
MySQL.transaction.await = originalTransaction

print(('Tests: %d, Failed: %d'):format(total, failed))
if failed > 0 then error(('Database tests failed: %d'):format(failed)) end
