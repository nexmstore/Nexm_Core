local Errors = NEXM_INTERNAL.Modules.Errors
local Validation = NEXM_INTERNAL.Modules.Validation
local Logger = NEXM_INTERNAL.Modules.Logger
local State = NEXM_INTERNAL.Modules.State
local Ownership = NEXM_INTERNAL.Modules.Ownership
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Health = NEXM_INTERNAL.Modules.Constants.HEALTH

local DB = {}

local function dbError(operation, rawError, ownerResource)
    local err = Errors.Create(
        Codes.DATABASE_ERROR,
        ('Database %s failed'):format(operation),
        { operation = operation }
    )

    Logger.Infrastructure(err, 'database', ownerResource)
    if Config and Config.Debug and rawError then
        Logger.Debug('Database debug detail', { rawError = tostring(rawError), operation = operation }, ownerResource)
    end

    return err
end

local function validateSql(sql)
    return Validation.String(sql, {
        name = 'sql',
        nonEmpty = true,
        min = 1,
        max = 65535
    })
end

local function execute(operation, fn, sql, params, ownerResource)
    local ok, validationErr = validateSql(sql)
    if not ok then
        return nil, validationErr
    end

    local owner = ownerResource or Ownership.Resolve()
    local success, result = pcall(fn, sql, params or {})
    if not success then
        return nil, dbError(operation, result, owner)
    end

    return result, nil
end

function DB.Connect()
    if GetResourceState and GetResourceState('oxmysql') ~= 'started' then
        local err = Errors.Create(
            Codes.DATABASE_UNAVAILABLE,
            'oxmysql is not started',
            { resource = 'oxmysql' }
        )
        State.SetComponent('database', Health.FAILED, { code = err.code })
        Logger.Infrastructure(err, 'database', 'nexm_core')
        return false, err
    end

    local query = Config and Config.Database and Config.Database.healthQuery or 'SELECT 1'
    local success, result = pcall(function()
        return MySQL.scalar.await(query)
    end)

    if not success then
        local err = dbError('connectivity check', result, 'nexm_core')
        State.SetComponent('database', Health.FAILED, { code = err.code })
        return false, err
    end

    State.SetComponent('database', Health.HEALTHY)
    return true, nil
end

function DB.Query(sql, params, ownerResource)
    return execute('query', MySQL.query.await, sql, params, ownerResource)
end

function DB.Single(sql, params, ownerResource)
    return execute('single', MySQL.single.await, sql, params, ownerResource)
end

function DB.Scalar(sql, params, ownerResource)
    return execute('scalar', MySQL.scalar.await, sql, params, ownerResource)
end

function DB.Insert(sql, params, ownerResource)
    return execute('insert', MySQL.insert.await, sql, params, ownerResource)
end

function DB.Update(sql, params, ownerResource)
    return execute('update', MySQL.update.await, sql, params, ownerResource)
end

function DB.Transaction(queries, sharedParams, ownerResource)
    local owner = ownerResource or Ownership.Resolve()

    local ok, validationErr = Validation.Table(queries, {
        name = 'transaction queries',
        minEntries = 1,
        maxEntries = 256
    })
    if not ok then
        return false, validationErr
    end

    local success, result = pcall(function()
        return MySQL.transaction.await(queries, sharedParams)
    end)

    if not success or result ~= true then
        return false, dbError('transaction', success and 'transaction returned false' or result, owner)
    end

    return true, nil
end

NEXM_INTERNAL.Modules.InternalDB = DB
NEXM_INTERNAL.Modules.DB = DB
