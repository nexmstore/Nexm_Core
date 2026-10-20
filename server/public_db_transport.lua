local DB = NEXM_INTERNAL.Modules.DB
local State = NEXM_INTERNAL.Modules.State
local Errors = NEXM_INTERNAL.Modules.Errors
local Constants = NEXM_INTERNAL.Modules.Constants
local Codes = Constants.ERROR_CODES

local REQUEST_EVENT = 'nexm_core:internal:public_db:request:v1'
local RESULT_EVENT = 'nexm_core:internal:public_db:result:v1'
local active = {}

local function validOwner(value)
    return type(value) == 'string' and value:match('^[%w%._%-]+$') ~= nil
end

local function resultKey(owner, requestId)
    return ('%s|%s'):format(owner, requestId)
end

local function emitResult(owner, payload)
    if type(GetResourceState) == 'function' and GetResourceState(owner) ~= 'started' then
        return
    end
    payload.owner = owner
    TriggerEvent(RESULT_EVENT, payload)
end

local function fail(owner, requestId, token, resultStyle, err)
    emitResult(owner, {
        requestId = requestId,
        token = token,
        success = false,
        resultStyle = resultStyle,
        error = err
    })
end

AddEventHandler(REQUEST_EVENT, function(payload)
    if type(payload) ~= 'table' then return end

    local claimedOwner = validOwner(payload.owner) and payload.owner or nil
    local invokingOwner = GetInvokingResource and GetInvokingResource() or nil
    invokingOwner = validOwner(invokingOwner) and invokingOwner or nil
    if invokingOwner and claimedOwner and invokingOwner ~= claimedOwner then return end
    local owner = invokingOwner or claimedOwner
    if not validOwner(owner) then return end

    local requestId = payload.requestId
    local token = payload.token
    local operation = payload.operation
    if type(requestId) ~= 'string' or requestId == '' or #requestId > 192 then return end
    if type(token) ~= 'string' or token == '' or #token > 256 then return end
    if type(operation) ~= 'string' then return end

    local key = resultKey(owner, requestId)
    if active[key] then
        fail(owner, requestId, token, operation == 'transaction' and 'predicate' or 'getter', Errors.Create(
            Codes.DATABASE_ERROR,
            'Duplicate public DB transport request',
            { operation = operation }
        ))
        return
    end

    active[key] = token

    CreateThread(function()
        local function finish(payloadResult)
            if active[key] ~= token then return end
            active[key] = nil
            emitResult(owner, payloadResult)
        end

        if not State.IsReady() then
            finish({
                requestId = requestId,
                token = token,
                success = false,
                resultStyle = operation == 'transaction' and 'predicate' or 'getter',
                error = Errors.Create(Codes.CORE_NOT_READY, 'NEXM Core is not ready', { state = State.Get() })
            })
            return
        end

        local result, err
        if operation == 'query' then
            result, err = DB.Query(payload.sql, payload.params, owner)
        elseif operation == 'single' then
            result, err = DB.Single(payload.sql, payload.params, owner)
        elseif operation == 'scalar' then
            result, err = DB.Scalar(payload.sql, payload.params, owner)
        elseif operation == 'insert' then
            result, err = DB.Insert(payload.sql, payload.params, owner)
        elseif operation == 'update' then
            result, err = DB.Update(payload.sql, payload.params, owner)
        elseif operation == 'transaction' then
            result, err = DB.Transaction(payload.queries, payload.sharedParams, owner)
        else
            finish({
                requestId = requestId,
                token = token,
                success = false,
                resultStyle = 'getter',
                error = Errors.Create(Codes.INVALID_ARGUMENT, 'Unsupported public DB transport operation', {
                    operation = operation
                })
            })
            return
        end

        finish({
            requestId = requestId,
            token = token,
            success = err == nil,
            resultStyle = operation == 'transaction' and 'predicate' or 'getter',
            result = result,
            error = err
        })
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if not validOwner(resourceName) or resourceName == GetCurrentResourceName() then return end
    local prefix = resourceName .. '|'
    for key in pairs(active) do
        if key:sub(1, #prefix) == prefix then
            -- Do not attempt to resume or return into a resource whose script
            -- environment is being destroyed. Any already-started DB operation
            -- may finish internally, but its result is intentionally orphaned.
            active[key] = nil
        end
    end
end)

NEXM_INTERNAL.Modules.PublicDBTransport = {
    RequestEvent = REQUEST_EVENT,
    ResultEvent = RESULT_EVENT
}
