-- Offline coroutine regression harness for NEXM Core hotfix.9.
-- It exercises Migrations.Run with DB operations that yield and resume, matching
-- the shape of the FiveM/oxmysql callback -> promise -> Citizen.Await path.

local total, failed = 0, 0
local function expect(name, condition)
    total = total + 1
    if condition then
        print(('[PASS] %s'):format(name))
    else
        failed = failed + 1
        print(('[FAIL] %s'):format(name))
    end
end

Config = { Debug = false, Database = { migrationDebug = false } }
GetConvarInt = function() return 0 end

local Codes = {
    INVALID_ARGUMENT = 'INVALID_ARGUMENT',
    DATABASE_ERROR = 'DATABASE_ERROR',
    MIGRATION_ERROR = 'MIGRATION_ERROR',
    MIGRATION_CHECKSUM_MISMATCH = 'MIGRATION_CHECKSUM_MISMATCH',
    REGISTRATION_EXISTS = 'REGISTRATION_EXISTS',
    OWNER_MISMATCH = 'OWNER_MISMATCH'
}

local Errors = {}
function Errors.Create(code, message, context)
    return { code = code, message = message, context = context or {} }
end
function Errors.Wrap(code, message, cause, context)
    context = context or {}
    if type(cause) == 'table' and cause.code then context.causeCode = cause.code end
    return Errors.Create(code, message, context)
end
function Errors.Is(value, code)
    return type(value) == 'table' and type(value.code) == 'string' and (code == nil or value.code == code)
end

local Validation = {}
function Validation.String(value, options)
    if type(value) ~= 'string' then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'expected string') end
    if options and options.nonEmpty and value == '' then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'empty') end
    if options and options.pattern and not value:match(options.pattern) then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'pattern') end
    return true, nil
end
function Validation.Table(value, options)
    if type(value) ~= 'table' then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'expected table') end
    local n = 0
    for _ in pairs(value) do n = n + 1 end
    if options and options.minEntries and n < options.minEntries then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'too small') end
    if options and options.maxEntries and n > options.maxEntries then return false, Errors.Create(Codes.INVALID_ARGUMENT, 'too large') end
    return true, nil
end

local Logger = { logs = {} }
for _, name in ipairs({ 'Warn', 'Info', 'Infrastructure', 'Debug' }) do
    Logger[name] = function(message, context, owner)
        Logger.logs[#Logger.logs + 1] = { level = name, message = message, context = context, owner = owner }
    end
end

local Ownership = {}
function Ownership.Resolve() return 'nexm_test' end
function Ownership.ValidateLocalName(value)
    if type(value) ~= 'string' or value == '' or not value:match('^[%w%._%-]+$') then
        return false, Errors.Create(Codes.INVALID_ARGUMENT, 'invalid local name')
    end
    return true, nil
end

local DB = { calls = {} }
local function yieldDb(op, payload)
    DB.calls[#DB.calls + 1] = { op = op, payload = payload }
    return coroutine.yield({ kind = 'db', op = op, payload = payload })
end
function DB.Query(sql, params, owner) return yieldDb('query', { sql = sql, params = params, owner = owner }) end
function DB.Insert(sql, params, owner) return yieldDb('insert', { sql = sql, params = params, owner = owner }) end
function DB.Transaction(queries, shared, owner) return yieldDb('transaction', { queries = queries, shared = shared, owner = owner }) end

NEXM_INTERNAL = { Modules = {
    InternalDB = DB,
    DB = DB,
    Errors = Errors,
    Validation = Validation,
    Logger = Logger,
    Ownership = Ownership,
    Constants = { ERROR_CODES = Codes }
} }

dofile('server/migrations.lua')
local Migrations = NEXM_INTERNAL.Modules.Migrations

local function resetResource(resource)
    Migrations.CleanupOwner(resource)
    DB.calls = {}
    Logger.logs = {}
end

local function register(resource, id, sql, transactional)
    local ok, err = Migrations.Register(resource, {
        id = id,
        statements = { sql or ('CREATE TABLE `' .. id .. '` (`id` INT)') },
        transactional = transactional
    }, resource)
    assert(ok, err and err.code or 'register failed')
    return Migrations.GetRegistered(resource)[id].checksum
end

local function runCoroutine(resource, responses, hook)
    local co = coroutine.create(function()
        return Migrations.Run(resource)
    end)
    local responseIndex = 1
    local ok, a, b = coroutine.resume(co)
    while ok and coroutine.status(co) ~= 'dead' do
        local request = a
        if hook then hook(responseIndex, request, co) end
        local response = responses[responseIndex]
        assert(response, ('missing response %d for %s'):format(responseIndex, request and request.op or '?'))
        responseIndex = responseIndex + 1
        ok, a, b = coroutine.resume(co, table.unpack(response, 1, response.n or #response))
    end
    if not ok then return nil, a, responseIndex - 1 end
    return a, b, responseIndex - 1
end

-- 1. clean migration apply via yielded Query + Transaction.
do
    local r = 'hf9_clean'
    resetResource(r)
    register(r, '001_initial', 'CREATE TABLE clean_test (id INT)')
    local ok, err, count = runCoroutine(r, {
        { n = 2, [1] = {}, [2] = nil },
        { n = 2, [1] = true, [2] = nil }
    })
    expect('clean async migration apply', ok == true and err == nil and count == 2)
end

-- 2. restart / already applied is skipped.
do
    local r = 'hf9_applied'
    resetResource(r)
    local checksum = register(r, '001_initial', 'CREATE TABLE applied_test (id INT)')
    local ok, err, count = runCoroutine(r, {
        { n = 2, [1] = { { migration = '001_initial', checksum = checksum } }, [2] = nil }
    })
    expect('already-applied migration skipped', ok == true and err == nil and count == 1)
end

-- 3. ordered migrations execute in lexical order.
do
    local r = 'hf9_order'
    resetResource(r)
    register(r, '002_second', 'CREATE TABLE second_test (id INT)')
    register(r, '001_first', 'CREATE TABLE first_test (id INT)')
    local seen = {}
    local ok, err = runCoroutine(r, {
        { n = 2, [1] = {}, [2] = nil },
        { n = 2, [1] = true, [2] = nil },
        { n = 2, [1] = true, [2] = nil }
    }, function(index, request)
        if request and request.op == 'transaction' then
            seen[#seen + 1] = request.payload.queries[1].query
        end
    end)
    expect('multiple migration order', ok == true and err == nil and seen[1]:find('first_test', 1, true) and seen[2]:find('second_test', 1, true))
end

-- 4. checksum match succeeds without execution.
do
    local r = 'hf9_checksum_match'
    resetResource(r)
    local checksum = register(r, '001_initial', 'CREATE TABLE checksum_match (id INT)')
    local ok, err = runCoroutine(r, {
        { n = 2, [1] = { { migration = '001_initial', checksum = checksum } }, [2] = nil }
    })
    expect('checksum match', ok == true and err == nil)
end

-- 5. checksum mismatch fails closed.
do
    local r = 'hf9_checksum_mismatch'
    resetResource(r)
    register(r, '001_initial', 'CREATE TABLE checksum_mismatch (id INT)')
    local ok, err = runCoroutine(r, {
        { n = 2, [1] = { { migration = '001_initial', checksum = 'adler32:deadbeef' } }, [2] = nil }
    })
    expect('checksum mismatch fails closed', ok == false and Errors.Is(err, Codes.MIGRATION_CHECKSUM_MISMATCH))
end

-- 6. load_applied DB error fails closed.
do
    local r = 'hf9_query_error'
    resetResource(r)
    register(r, '001_initial', 'CREATE TABLE query_error (id INT)')
    local dbErr = Errors.Create(Codes.DATABASE_ERROR, 'forced query failure')
    local ok, err = runCoroutine(r, {
        { n = 2, [1] = nil, [2] = dbErr }
    })
    expect('DB query error fails migration', ok == false and Errors.Is(err, Codes.MIGRATION_ERROR) and err.context.causeCode == Codes.DATABASE_ERROR)
end

-- 7. non-transactional bookkeeping INSERT error fails closed.
do
    local r = 'hf9_bookkeeping_error'
    resetResource(r)
    register(r, '001_initial', 'CREATE TABLE bookkeeping_error (id INT)', false)
    local dbErr = Errors.Create(Codes.DATABASE_ERROR, 'forced insert failure')
    local ok, err = runCoroutine(r, {
        { n = 2, [1] = {}, [2] = nil },
        { n = 2, [1] = {}, [2] = nil },
        { n = 2, [1] = nil, [2] = dbErr }
    })
    expect('bookkeeping insert error fails migration', ok == false and Errors.Is(err, Codes.MIGRATION_ERROR))
end

-- 8. duplicate Run returns structured failure while first run is suspended.
do
    local r = 'hf9_duplicate_run'
    resetResource(r)
    register(r, '001_initial', 'CREATE TABLE duplicate_run (id INT)')
    local duplicateOk, duplicateErr
    local ok, err = runCoroutine(r, {
        { n = 2, [1] = {}, [2] = nil },
        { n = 2, [1] = true, [2] = nil }
    }, function(index)
        if index == 1 then duplicateOk, duplicateErr = Migrations.Run(r) end
    end)
    expect('duplicate Run blocked during async wait', ok == true and err == nil and duplicateOk == false and Errors.Is(duplicateErr, Codes.MIGRATION_ERROR))
end

-- 9. migration statement failure is propagated and bookkeeping is not attempted.
do
    local r = 'hf9_statement_failure'
    resetResource(r)
    register(r, '001_initial', 'ALTER TABLE does_not_matter ADD COLUMN x INT', false)
    local dbErr = Errors.Create(Codes.DATABASE_ERROR, 'forced statement failure')
    local ok, err, count = runCoroutine(r, {
        { n = 2, [1] = {}, [2] = nil },
        { n = 2, [1] = nil, [2] = dbErr }
    })
    expect('migration statement failure retained', ok == false and Errors.Is(err, Codes.MIGRATION_ERROR) and count == 2)
end

-- 10. restart after a failed migration can retry because no applied record was written.
do
    local r = 'hf9_retry_after_failure'
    resetResource(r)
    register(r, '001_initial', 'ALTER TABLE retry_test ADD COLUMN x INT', false)
    local dbErr = Errors.Create(Codes.DATABASE_ERROR, 'forced first failure')
    local firstOk = runCoroutine(r, {
        { n = 2, [1] = {}, [2] = nil },
        { n = 2, [1] = nil, [2] = dbErr }
    })
    local secondOk, secondErr = runCoroutine(r, {
        { n = 2, [1] = {}, [2] = nil },
        { n = 2, [1] = {}, [2] = nil },
        { n = 2, [1] = 1, [2] = nil }
    })
    expect('restart after failed migration retries safely', firstOk == false and secondOk == true and secondErr == nil)
end

-- 11. schema=16 style restart: all applied records match, no execution calls.
do
    local r = 'hf9_schema16'
    resetResource(r)
    local rows = {}
    for i = 1, 16 do
        local id = ('%03d_migration'):format(i)
        local checksum = register(r, id, ('CREATE TABLE schema16_%02d (id INT)'):format(i))
        rows[#rows + 1] = { migration = id, checksum = checksum }
    end
    local ok, err, count = runCoroutine(r, {
        { n = 2, [1] = rows, [2] = nil }
    })
    expect('schema=16 already-applied restart', ok == true and err == nil and count == 1)
end

-- 12. duplicate rows in tracking result fail closed.
do
    local r = 'hf9_duplicate_rows'
    resetResource(r)
    local checksum = register(r, '001_initial', 'CREATE TABLE duplicate_rows (id INT)')
    local ok, err = runCoroutine(r, {
        { n = 2, [1] = {
            { migration = '001_initial', checksum = checksum },
            { migration = '001_initial', checksum = checksum }
        }, [2] = nil }
    })
    expect('duplicate tracking rows fail closed', ok == false and Errors.Is(err, Codes.MIGRATION_ERROR))
end

-- 13. cleanupPending survives async wait and clears registry after completion.
do
    local r = 'hf9_cleanup_pending'
    resetResource(r)
    register(r, '001_initial', 'CREATE TABLE cleanup_pending (id INT)')
    local ok, err = runCoroutine(r, {
        { n = 2, [1] = {}, [2] = nil },
        { n = 2, [1] = true, [2] = nil }
    }, function(index)
        if index == 1 then Migrations.CleanupOwner(r) end
    end)
    local registered = Migrations.GetRegistered(r)
    expect('cleanupPending preserved across async run', ok == true and err == nil and next(registered) == nil)
end

-- 14. async result actually suspends before returning and then resumes to success.
do
    local r = 'hf9_async_resume'
    resetResource(r)
    register(r, '001_initial', 'CREATE TABLE async_resume (id INT)')
    local co = coroutine.create(function() return Migrations.Run(r) end)
    local firstOk, request = coroutine.resume(co)
    local suspended = firstOk and coroutine.status(co) == 'suspended' and type(request) == 'table' and request.op == 'query'
    local secondOk, request2 = coroutine.resume(co, {}, nil)
    local suspendedAgain = secondOk and coroutine.status(co) == 'suspended' and type(request2) == 'table' and request2.op == 'transaction'
    local thirdOk, result, err = coroutine.resume(co, true, nil)
    expect('migration run async suspend/resume', suspended and suspendedAgain and thirdOk and coroutine.status(co) == 'dead' and result == true and err == nil)
end

print(('RESULT tests=%d pass=%d fail=%d'):format(total, total - failed, failed))
if failed > 0 then os.exit(1) end
