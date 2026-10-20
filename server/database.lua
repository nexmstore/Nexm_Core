local Errors = NEXM_INTERNAL.Modules.Errors
local Validation = NEXM_INTERNAL.Modules.Validation
local Logger = NEXM_INTERNAL.Modules.Logger
local State = NEXM_INTERNAL.Modules.State
local Ownership = NEXM_INTERNAL.Modules.Ownership
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local Health = NEXM_INTERNAL.Modules.Constants.HEALTH

local DB = {}

local function dbError(operation, rawError, ownerResource, context)
    context = type(context) == 'table' and context or {}
    context.operation = operation

    local err = Errors.Create(
        Codes.DATABASE_ERROR,
        ('Database %s failed'):format(operation),
        context
    )

    Logger.Infrastructure(err, 'database', ownerResource)
    if Config and Config.Debug and rawError then
        Logger.Debug('Database debug detail', {
            rawError = tostring(rawError),
            operation = operation,
            sql = context.sql,
            paramCount = context.paramCount
        }, ownerResource)
    end

    return err
end

local function dbParamsError(operation, message, ownerResource, context)
    context = type(context) == 'table' and context or {}
    context.operation = operation

    local err = Errors.Create(
        Codes.DATABASE_INVALID_PARAMS or Codes.INVALID_ARGUMENT,
        message,
        context
    )

    Logger.Infrastructure(err, 'database', ownerResource)
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

local function compactSql(sql)
    if type(sql) ~= 'string' then return nil end
    local compact = sql:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #compact > 512 then compact = compact:sub(1, 512) .. '...' end
    return compact
end

local function tableParameterShape(params)
    if params == nil then
        return {
            numericCount = 0,
            maxNumericIndex = 0,
            namedStringCount = 0,
            numericStringCount = 0,
            otherKeyCount = 0,
            entryCount = 0,
            sparse = false,
            duplicateIndex = false
        }
    end

    if type(params) ~= 'table' then return nil end

    local shape = {
        numericCount = 0,
        maxNumericIndex = 0,
        namedStringCount = 0,
        numericStringCount = 0,
        otherKeyCount = 0,
        entryCount = 0,
        sparse = false,
        duplicateIndex = false
    }
    local seenIndexes = {}

    for key in pairs(params) do
        shape.entryCount = shape.entryCount + 1
        local positionalIndex

        if type(key) == 'number' then
            if key >= 1 and key % 1 == 0 then
                positionalIndex = key
                shape.numericCount = shape.numericCount + 1
            else
                shape.otherKeyCount = shape.otherKeyCount + 1
            end
        elseif type(key) == 'string' then
            local numericKey = key:match('^(%d+)$')
            local parsed = numericKey and tonumber(numericKey) or nil
            if parsed and parsed >= 1 and parsed % 1 == 0 then
                positionalIndex = parsed
                shape.numericStringCount = shape.numericStringCount + 1
            else
                shape.namedStringCount = shape.namedStringCount + 1
            end
        else
            shape.otherKeyCount = shape.otherKeyCount + 1
        end

        if positionalIndex then
            if seenIndexes[positionalIndex] then shape.duplicateIndex = true end
            seenIndexes[positionalIndex] = true
            if positionalIndex > shape.maxNumericIndex then shape.maxNumericIndex = positionalIndex end
        end
    end

    local positionalCount = shape.numericCount + shape.numericStringCount
    if positionalCount > 0 then
        shape.sparse = positionalCount ~= shape.maxNumericIndex
        if not shape.sparse then
            for index = 1, shape.maxNumericIndex do
                if not seenIndexes[index] then
                    shape.sparse = true
                    break
                end
            end
        end
    end

    shape.positionalCount = positionalCount
    return shape
end

local function positionalValue(params, index)
    local value = rawget(params, index)
    if value ~= nil then return value end
    return rawget(params, tostring(index))
end

-- Rewrites only real positional placeholders. Question marks inside quoted strings,
-- backticks, and SQL comments are deliberately ignored.
local function rewriteSparsePositionalParams(sql, params, ownerResource, operation)
    local shape = tableParameterShape(params)
    if not shape then
        return nil, nil, dbParamsError(
            operation,
            'Database parameters must be a table when provided',
            ownerResource,
            { parameterType = type(params), sql = compactSql(sql) }
        )
    end

    if shape.otherKeyCount > 0 or shape.duplicateIndex then
        return nil, nil, dbParamsError(
            operation,
            'Database parameters contain unsupported table keys',
            ownerResource,
            { sql = compactSql(sql), paramCount = shape.entryCount }
        )
    end

    -- Preserve historical behaviour for normal dense arrays and named-parameter
    -- objects. The compatibility fix is intentionally limited to sparse numeric
    -- positional tables, which Lua/CFX cannot serialize as a true array safely.
    if not shape.sparse then
        return sql, params or {}, nil
    end

    if shape.namedStringCount > 0 then
        return nil, nil, dbParamsError(
            operation,
            'Sparse positional parameters cannot be mixed with named parameters',
            ownerResource,
            { sql = compactSql(sql), paramCount = shape.entryCount }
        )
    end

    local output = {}
    local dense = {}
    local placeholderIndex = 0
    local length = #sql
    local index = 1
    local state = 'normal'

    local function append(value)
        output[#output + 1] = value
    end

    while index <= length do
        local current = sql:sub(index, index)
        local nextChar = index < length and sql:sub(index + 1, index + 1) or ''

        if state == 'normal' then
            if current == "'" then
                append(current)
                state = 'single_quote'
            elseif current == '"' then
                append(current)
                state = 'double_quote'
            elseif current == '`' then
                append(current)
                state = 'backtick'
            elseif current == '-' and nextChar == '-' then
                append('--')
                index = index + 1
                state = 'line_comment'
            elseif current == '#' then
                append(current)
                state = 'line_comment'
            elseif current == '/' and nextChar == '*' then
                append('/*')
                index = index + 1
                state = 'block_comment'
            elseif current == '?' then
                placeholderIndex = placeholderIndex + 1
                local value = positionalValue(params, placeholderIndex)
                if value == nil then
                    append('NULL')
                else
                    append('?')
                    dense[#dense + 1] = value
                end
            else
                append(current)
            end
        elseif state == 'single_quote' then
            append(current)
            if current == '\\' and nextChar ~= '' then
                append(nextChar)
                index = index + 1
            elseif current == "'" then
                if nextChar == "'" then
                    append(nextChar)
                    index = index + 1
                else
                    state = 'normal'
                end
            end
        elseif state == 'double_quote' then
            append(current)
            if current == '\\' and nextChar ~= '' then
                append(nextChar)
                index = index + 1
            elseif current == '"' then
                if nextChar == '"' then
                    append(nextChar)
                    index = index + 1
                else
                    state = 'normal'
                end
            end
        elseif state == 'backtick' then
            append(current)
            if current == '`' then
                if nextChar == '`' then
                    append(nextChar)
                    index = index + 1
                else
                    state = 'normal'
                end
            end
        elseif state == 'line_comment' then
            append(current)
            if current == '\n' or current == '\r' then state = 'normal' end
        elseif state == 'block_comment' then
            if current == '*' and nextChar == '/' then
                append('*/')
                index = index + 1
                state = 'normal'
            else
                append(current)
            end
        end

        index = index + 1
    end

    -- An interior nil is recoverable because a later numeric key proves the
    -- caller intended a positional NULL. Missing trailing parameters are not
    -- distinguishable from an incomplete call, so fail closed instead.
    if placeholderIndex ~= shape.maxNumericIndex then
        return nil, nil, dbParamsError(
            operation,
            'Sparse positional parameter count does not match SQL placeholders',
            ownerResource,
            {
                sql = compactSql(sql),
                placeholderCount = placeholderIndex,
                highestParameterIndex = shape.maxNumericIndex,
                suppliedParameterCount = shape.positionalCount
            }
        )
    end

    if Config and Config.Debug then
        Logger.Debug('Normalized sparse positional database parameters', {
            operation = operation,
            sql = compactSql(sql),
            placeholderCount = placeholderIndex,
            suppliedParameterCount = shape.positionalCount,
            normalizedParameterCount = #dense,
            nullCount = placeholderIndex - #dense
        }, ownerResource)
    end

    return table.concat(output), dense, nil
end

local function normalizeSqlParams(sql, params, ownerResource, operation)
    if params == nil then return sql, {}, nil end
    if type(params) ~= 'table' then
        return nil, nil, dbParamsError(
            operation,
            'Database parameters must be a table when provided',
            ownerResource,
            { parameterType = type(params), sql = compactSql(sql) }
        )
    end

    return rewriteSparsePositionalParams(sql, params, ownerResource, operation)
end

-- Hotfix.9 DB transport: oxmysql must never receive a Lua callback function
-- reference from nexm_core. The live hotfix.8 run proved the SQL succeeds, but
-- CFX still reports a script-host function-reference failure around the callback
-- boundary. Route DB work through a tiny Core-owned JS bridge instead. The JS
-- bridge awaits oxmysql's *_async export and returns a plain local event payload
-- to Lua. Public NEXM.DB return contracts remain unchanged.
local DB_BRIDGE_REQUEST_EVENT = 'nexm_core:internal:db:request:v2'
local DB_BRIDGE_RESULT_EVENT = 'nexm_core:internal:db:result:v2'
local DB_BRIDGE_TIMEOUT_MS = 30000
local dbBridgeSequence = 0
local dbBridgePending = {}

local function migrationDebugEnabled()
    return GetConvarInt and GetConvarInt('nexm_debug_migrations', 0) == 1
end

local function bridgeDiag(stage, operation, owner, extra)
    if not migrationDebugEnabled() then return end
    extra = type(extra) == 'table' and extra or {}
    print(('[DB BRIDGE DIAG] stage=%s operation=%s owner=%s request=%s success=%s'):format(
        tostring(stage), tostring(operation), tostring(owner), tostring(extra.requestId or '<none>'),
        tostring(extra.success)
    ))
end

local function nextBridgeRequestId(owner)
    dbBridgeSequence = dbBridgeSequence + 1
    local now = GetGameTimer and GetGameTimer() or 0
    return ('%s:%s:%s'):format(tostring(owner or 'nexm_core'), tostring(now), tostring(dbBridgeSequence))
end

AddEventHandler(DB_BRIDGE_RESULT_EVENT, function(payload)
    if type(payload) ~= 'table' then return end
    local requestId = payload.requestId
    local pending = type(requestId) == 'string' and dbBridgePending[requestId] or nil
    if not pending or payload.token ~= pending.token then return end

    dbBridgePending[requestId] = nil
    bridgeDiag('result_event', pending.operation, pending.owner, {
        requestId = requestId,
        success = payload.ok == true
    })

    local envelope = {
        ok = payload.ok == true,
        result = payload.result,
        error = payload.error
    }

    -- The JS->Lua event callback itself returns before the waiting Lua coroutine
    -- resumes. This keeps the event callback out of the resumed DB call stack.
    if type(SetTimeout) == 'function' then
        SetTimeout(0, function()
            pending.promise:resolve(envelope)
        end)
    else
        CreateThread(function()
            Wait(0)
            pending.promise:resolve(envelope)
        end)
    end
end)

local function invokeBridge(operation, bridgeOperation, sqlOrQueries, params, ownerResource)
    local owner = ownerResource or Ownership.Resolve()
    if type(promise) ~= 'table' or type(promise.new) ~= 'function'
        or type(Citizen) ~= 'table' or type(Citizen.Await) ~= 'function'
        or type(TriggerEvent) ~= 'function' then
        return nil, dbError(operation, 'database bridge runtime unavailable', owner, {
            phase = 'bridge_runtime'
        })
    end

    local requestId = nextBridgeRequestId(owner)
    local token = ('%s|%s|dbv2'):format(tostring(owner), requestId)
    local p = promise.new()
    dbBridgePending[requestId] = {
        token = token,
        promise = p,
        operation = operation,
        owner = owner
    }

    if type(SetTimeout) == 'function' then
        SetTimeout(DB_BRIDGE_TIMEOUT_MS, function()
            local pending = dbBridgePending[requestId]
            if not pending or pending.token ~= token then return end
            dbBridgePending[requestId] = nil
            pending.promise:resolve({
                ok = false,
                error = ('NEXM DB bridge timeout after %sms'):format(DB_BRIDGE_TIMEOUT_MS)
            })
        end)
    end

    local payload = {
        requestId = requestId,
        token = token,
        operation = bridgeOperation,
        owner = owner,
        params = params or {}
    }
    if bridgeOperation == 'transaction' then
        payload.queries = sqlOrQueries
    else
        payload.sql = sqlOrQueries
    end

    bridgeDiag('request', operation, owner, { requestId = requestId })
    TriggerEvent(DB_BRIDGE_REQUEST_EVENT, payload)

    local envelope = Citizen.Await(p)
    bridgeDiag('await_resumed', operation, owner, {
        requestId = requestId,
        success = type(envelope) == 'table' and envelope.ok == true
    })

    if type(envelope) ~= 'table' or envelope.ok ~= true then
        local rawError = type(envelope) == 'table' and envelope.error or 'missing database bridge result envelope'
        local context = {
            phase = 'bridge_result'
        }
        if type(sqlOrQueries) == 'string' then
            context.sql = compactSql(sqlOrQueries)
            context.paramCount = (tableParameterShape(params) or {}).entryCount or 0
        elseif type(sqlOrQueries) == 'table' then
            context.queryCount = #sqlOrQueries
        end
        return nil, dbError(operation, rawError, owner, context)
    end

    return envelope.result, nil
end

local function execute(operation, bridgeOperation, sql, params, ownerResource)
    local ok, validationErr = validateSql(sql)
    if not ok then return nil, validationErr end

    local owner = ownerResource or Ownership.Resolve()
    local normalizedSql, normalizedParams, paramsErr = normalizeSqlParams(sql, params, owner, operation)
    if not normalizedSql then return nil, paramsErr end

    return invokeBridge(operation, bridgeOperation, normalizedSql, normalizedParams, owner)
end

local function normalizeTransactionQueries(queries, sharedParams, ownerResource)
    local numericCount, maxIndex = 0, 0
    for key in pairs(queries) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then
            return nil, nil, dbParamsError(
                'transaction',
                'Transaction query list must be a dense numeric array',
                ownerResource
            )
        end
        numericCount = numericCount + 1
        if key > maxIndex then maxIndex = key end
    end

    if numericCount ~= maxIndex then
        return nil, nil, dbParamsError(
            'transaction',
            'Transaction query list must not contain sparse entries',
            ownerResource,
            { queryCount = numericCount, highestQueryIndex = maxIndex }
        )
    end

    if sharedParams ~= nil and type(sharedParams) ~= 'table' then
        return nil, nil, dbParamsError(
            'transaction',
            'Transaction shared parameters must be a table when provided',
            ownerResource,
            { parameterType = type(sharedParams) }
        )
    end

    local normalized = {}

    for queryIndex = 1, maxIndex do
        local entry = queries[queryIndex]
        if type(entry) == 'string' then
            if sharedParams ~= nil then
                local sql, params, err = normalizeSqlParams(entry, sharedParams, ownerResource, 'transaction')
                if not sql then return nil, nil, err end
                normalized[#normalized + 1] = { query = sql, values = params }
            else
                normalized[#normalized + 1] = entry
            end
        elseif type(entry) == 'table' then
            local sql
            local params

            if type(entry.query) == 'string' then
                sql = entry.query
                params = entry.parameters ~= nil and entry.parameters or entry.values
            elseif type(entry[1]) == 'string' then
                sql = entry[1]
                params = entry[2]
            else
                return nil, nil, dbParamsError(
                    'transaction',
                    'Transaction query descriptor is invalid',
                    ownerResource,
                    { queryIndex = queryIndex }
                )
            end

            local validSql, sqlErr = validateSql(sql)
            if not validSql then return nil, nil, sqlErr end

            local normalizedSql, normalizedParams, paramsErr = normalizeSqlParams(
                sql,
                params,
                ownerResource,
                'transaction'
            )
            if not normalizedSql then return nil, nil, paramsErr end

            normalized[#normalized + 1] = {
                query = normalizedSql,
                values = normalizedParams
            }
        else
            return nil, nil, dbParamsError(
                'transaction',
                'Transaction query must be a SQL string or query descriptor',
                ownerResource,
                { queryIndex = queryIndex, queryType = type(entry) }
            )
        end
    end

    return normalized, nil, nil
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
    local result, err = execute('connectivity check', 'scalar', query, {}, 'nexm_core')
    if err then
        State.SetComponent('database', Health.FAILED, { code = err.code })
        return false, err
    end
    if result == nil then
        local nilErr = dbError('connectivity check', 'health query returned nil', 'nexm_core', {
            phase = 'result', sql = compactSql(query), paramCount = 0
        })
        State.SetComponent('database', Health.FAILED, { code = nilErr.code })
        return false, nilErr
    end

    State.SetComponent('database', Health.HEALTHY)
    return true, nil
end

function DB.Query(sql, params, ownerResource)
    return execute('query', 'query', sql, params, ownerResource)
end

function DB.Single(sql, params, ownerResource)
    return execute('single', 'single', sql, params, ownerResource)
end

function DB.Scalar(sql, params, ownerResource)
    return execute('scalar', 'scalar', sql, params, ownerResource)
end

function DB.Insert(sql, params, ownerResource)
    return execute('insert', 'insert', sql, params, ownerResource)
end

function DB.Update(sql, params, ownerResource)
    return execute('update', 'update', sql, params, ownerResource)
end

function DB.Transaction(queries, sharedParams, ownerResource)
    local owner = ownerResource or Ownership.Resolve()

    local ok, validationErr = Validation.Table(queries, {
        name = 'transaction queries',
        minEntries = 1,
        maxEntries = 256
    })
    if not ok then return false, validationErr end

    local normalizedQueries, normalizedSharedParams, normalizeErr = normalizeTransactionQueries(
        queries,
        sharedParams,
        owner
    )
    if not normalizedQueries then return false, normalizeErr end

    local result, err = invokeBridge('transaction', 'transaction', normalizedQueries, normalizedSharedParams or {}, owner)
    if err then return false, err end
    if result ~= true then
        return false, dbError('transaction', 'transaction returned false', owner, {
            phase = 'result', queryCount = #normalizedQueries
        })
    end

    return true, nil
end

NEXM_INTERNAL.Modules.InternalDB = DB
NEXM_INTERNAL.Modules.DB = DB
