local Framework = NEXM_INTERNAL.Managers.Framework
local Cache = NEXM_INTERNAL.Modules.PlayerCache
local Identity = NEXM_INTERNAL.Modules.Identity
local Validation = NEXM_INTERNAL.Modules.Validation
local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local Player = {}

local function capability(caps, ...)
    local current = caps
    for i = 1, select('#', ...) do
        if type(current) ~= 'table' then return false end
        current = current[select(i, ...)]
    end
    return current == true
end
local function unsupported(feature, framework)
    return nil, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Active framework does not support this capability', {
        feature = feature, framework = framework
    })
end
local function validateSource(source)
    return Validation.Source(source, { name = 'source' })
end

function Player.BuildSnapshot(source, adapter)
    adapter = adapter or Framework.GetSelected()
    if not adapter then return nil, Errors.Create(Codes.FRAMEWORK_UNAVAILABLE, 'No active framework adapter') end
    local caps = adapter.metadata.capabilities
    local frameworkName = adapter.metadata.name

    if not capability(caps, 'player', 'identity', 'character') then
        return unsupported('player.identity.character', frameworkName)
    end

    local rawCharacter, err = adapter.GetCharacterIdentifier(source)
    if not rawCharacter then return nil, err end
    local canonical, canonicalErr = Identity.CanonicalCharacter(frameworkName, rawCharacter)
    if not canonical then return nil, canonicalErr end

    local account = nil
    if capability(caps, 'player', 'identity', 'account') then
        account, err = adapter.GetAccountIdentifier(source)
        if not account then return nil, err end
    end

    local license = nil
    if capability(caps, 'player', 'identity', 'license') then
        license, err = adapter.GetLicense(source)
        if not license then return nil, err end
    end

    local name, nameErr = adapter.GetCharacterName(source)
    if not name then return nil, nameErr end

    local job = nil
    if capability(caps, 'player', 'job') then
        job, err = adapter.GetJob(source)
        if not job then return nil, err end
        if capability(caps, 'player', 'duty') then
            if type(job.onDuty) ~= 'boolean' then
                return nil, Errors.Create(Codes.ADAPTER_ERROR, 'Framework declared duty support but returned no boolean duty state', {
                    framework = frameworkName, source = source
                })
            end
        else
            job.onDuty = nil
        end
    end

    return {
        source = source,
        identifier = canonical,
        identity = {
            character = tostring(rawCharacter),
            account = account and tostring(account) or nil,
            license = license and tostring(license) or nil,
            provider = frameworkName
        },
        name = tostring(name),
        job = job,
        framework = frameworkName,
        loaded = true
    }, nil
end

local function requirePlayer(source)
    local ok, err = validateSource(source)
    if not ok then return nil, err end
    local adapter, frameworkErr = Framework.RequireHealthy()
    if frameworkErr then return nil, frameworkErr end
    local caps = adapter.metadata.capabilities
    if not (caps.player and caps.player.identity and caps.player.identity.character == true) then
        return unsupported('player.identity.character', adapter.metadata.name)
    end
    local snapshot = Cache.Get(source)
    if not snapshot then
        return nil, Errors.Create(Codes.PLAYER_NOT_FOUND, 'Normalized player was not found', { source = source })
    end
    return snapshot, nil
end

function Player.Get(source) return requirePlayer(source) end
function Player.Exists(source)
    local ok, err = validateSource(source)
    if not ok then return false, err end
    local _, frameworkErr = Framework.RequireHealthy()
    if frameworkErr then return false, frameworkErr end
    return Cache.Get(source) ~= nil, nil
end
function Player.GetIdentifier(source)
    local p, err = requirePlayer(source); if not p then return nil, err end
    return p.identifier, nil
end
function Player.GetCharacterIdentifier(source)
    local p, err = requirePlayer(source); if not p then return nil, err end
    if not p.identity or p.identity.character == nil then return unsupported('player.identity.character', p.framework) end
    return p.identity.character, nil
end
function Player.GetAccountIdentifier(source)
    local p, err = requirePlayer(source); if not p then return nil, err end
    if not p.identity or p.identity.account == nil then return unsupported('player.identity.account', p.framework) end
    return p.identity.account, nil
end
function Player.GetLicense(source)
    local ok, err = validateSource(source); if not ok then return nil, err end
    local adapter, frameworkErr = Framework.RequireHealthy(); if not adapter then return nil, frameworkErr end
    local caps = adapter.metadata.capabilities
    if not (caps.player and caps.player.identity and caps.player.identity.license == true) then
        return unsupported('player.identity.license', adapter.metadata.name)
    end
    local cached = Cache.Get(source)
    if cached and cached.identity and cached.identity.license then return cached.identity.license, nil end
    return adapter.GetLicense(source)
end
function Player.GetCharacterName(source)
    local p, err = requirePlayer(source); if not p then return nil, err end
    return p.name, nil
end
function Player.GetJob(source)
    local p, err = requirePlayer(source); if not p then return nil, err end
    if p.job == nil then return unsupported('player.job', p.framework) end
    local copy = Cache.Get(source)
    return copy.job, nil
end
function Player.GetJobGrade(source)
    local job, err = Player.GetJob(source); if not job then return nil, err end
    return job.grade, nil
end
function Player.GetSource(identifier)
    local valid, err = Validation.Identifier(identifier, { name = 'canonical character identifier', max = 256 })
    if not valid then return nil, err end
    local _, frameworkErr = Framework.RequireHealthy(); if frameworkErr then return nil, frameworkErr end
    local source = Cache.GetSource(identifier)
    if not source then return nil, Errors.Create(Codes.PLAYER_NOT_FOUND, 'Character is not online', { identifier = identifier }) end
    return source, nil
end
function Player.IsOnline(identifier)
    local valid, err = Validation.Identifier(identifier, { name = 'canonical character identifier', max = 256 })
    if not valid then return false, err end
    local _, frameworkErr = Framework.RequireHealthy(); if frameworkErr then return false, frameworkErr end
    return Cache.IsOnline(identifier), nil
end
function Player.GetFrameworkObject(source)
    local ok, err = validateSource(source); if not ok then return nil, err end
    local adapter, frameworkErr = Framework.RequireHealthy(); if not adapter then return nil, frameworkErr end
    local raw = adapter.GetPlayer(source)
    if not raw then return nil, Errors.Create(Codes.PLAYER_NOT_FOUND, 'Framework player object was not found', { source = source }) end
    return raw, nil
end

NEXM_INTERNAL.Modules.Player = Player
