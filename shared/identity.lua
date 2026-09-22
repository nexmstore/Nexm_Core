local Errors = NEXM_INTERNAL.Modules.Errors
local Validation = NEXM_INTERNAL.Modules.Validation
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES

local Identity = {}

function Identity.CanonicalCharacter(provider, rawIdentifier)
    local ok, err = Validation.String(provider, {
        name = 'identity provider', nonEmpty = true, min = 1, max = 32,
        pattern = '^[%w_%-]+$'
    })
    if not ok then return nil, err end

    if type(rawIdentifier) == 'number' then
        rawIdentifier = tostring(rawIdentifier)
    end

    ok, err = Validation.Identifier(rawIdentifier, {
        name = 'character identifier', min = 1, max = 220
    })
    if not ok then
        return nil, Errors.Wrap(
            Codes.INVALID_PLAYER_IDENTITY,
            'Framework returned an invalid active character identifier',
            err,
            { provider = provider }
        )
    end

    return ('%s:character:%s'):format(provider, rawIdentifier), nil
end

NEXM_INTERNAL.Modules.Identity = Identity
