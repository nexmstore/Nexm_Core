local Migrations = NEXM_INTERNAL.Modules.Migrations
local Errors = NEXM_INTERNAL.Modules.Errors
local Validation = NEXM_INTERNAL.Modules.Validation
local Transport = NEXM_INTERNAL.Modules.Transport
local Constants = NEXM_INTERNAL.Modules.Constants
local Codes = Constants.ERROR_CODES

local REQUEST_EVENT = 'nexm_core:internal:migrations:run:v1'
local RESULT_EVENT = 'nexm_core:internal:migrations:result:v1'
local activeRequests = {}

local function reply(requestId, token, owner, ok, err)
    TriggerEvent(RESULT_EVENT, {
        requestId = requestId,
        token = token,
        owner = owner,
        envelope = Transport.Pack(ok, err)
    })
end

local function invalidRequest(requestId, token, owner, message, context)
    reply(requestId, token, owner, false, Errors.Create(
        Codes.INVALID_ARGUMENT,
        message,
        context or {}
    ))
end

-- Intentionally server-local only. Do not RegisterNetEvent: clients must not be
-- able to invoke migration execution. TriggerEvent server->server preserves the
-- invoking resource so Core can bind the request to the real owner.
AddEventHandler(REQUEST_EVENT, function(request)
    local invoking = GetInvokingResource and GetInvokingResource() or nil
    local requestId = type(request) == 'table' and request.requestId or nil
    local token = type(request) == 'table' and request.token or nil
    local claimedOwner = type(request) == 'table' and request.owner or nil

    if type(requestId) ~= 'string' or requestId == '' or #requestId > 256
        or type(token) ~= 'string' or token == '' or #token > 512 then
        return invalidRequest(requestId, token, invoking or claimedOwner, 'Invalid migration transport request')
    end

    if type(invoking) ~= 'string' or invoking == '' then
        return invalidRequest(requestId, token, claimedOwner, 'Migration transport could not resolve invoking resource')
    end

    if claimedOwner ~= invoking then
        return reply(requestId, token, invoking, false, Errors.Create(
            Codes.OWNER_MISMATCH,
            'Migration transport owner does not match invoking resource',
            { ownerResource = invoking, requestedResource = claimedOwner }
        ))
    end

    if request.buildId ~= Constants.BUILD_ID then
        return reply(requestId, token, invoking, false, Errors.Create(
            Codes.INTEGRATION_ERROR,
            'Migration transport build identity mismatch',
            { resource = invoking, expectedBuild = Constants.BUILD_ID }
        ))
    end

    local validOwner, ownerErr = Validation.String(invoking, {
        name = 'migration resource',
        nonEmpty = true,
        min = 1,
        max = 128,
        pattern = '^[%w%._%-]+$'
    })
    if not validOwner then
        return reply(requestId, token, invoking, false, ownerErr)
    end

    activeRequests[invoking] = activeRequests[invoking] or {}
    local existingToken = activeRequests[invoking][requestId]
    if existingToken ~= nil then
        -- Same request replay while the original is active: ignore it so a
        -- duplicate failure cannot race the original successful response.
        if existingToken == token then return end
        return reply(requestId, token, invoking, false, Errors.Create(
            Codes.MIGRATION_ERROR,
            'Migration transport request id is already active',
            { resource = invoking }
        ))
    end
    activeRequests[invoking][requestId] = token

    -- Critical boundary rule: the event handler itself does not yield and does
    -- not wrap the asynchronous migration path in pcall/xpcall. DB awaits run in
    -- this Core-owned coroutine, outside any cross-resource function reference.
    CreateThread(function()
        local ok, err = Migrations.Run(invoking)

        local ownerRequests = activeRequests[invoking]
        if ownerRequests and ownerRequests[requestId] == token then
            ownerRequests[requestId] = nil
            if next(ownerRequests) == nil then activeRequests[invoking] = nil end
            reply(requestId, token, invoking, ok == true, err)
        end
    end)
end)

NEXM_INTERNAL.Modules.MigrationTransport = {
    RequestEvent = REQUEST_EVENT,
    ResultEvent = RESULT_EVENT
}
