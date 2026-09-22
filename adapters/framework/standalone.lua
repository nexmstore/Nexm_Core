local Errors = NEXM_INTERNAL.Modules.Errors
local Codes = NEXM_INTERNAL.Modules.Constants.ERROR_CODES
local adapter = {
    metadata = {
        name = 'standalone', resource = 'standalone', version = '1.0.0',
        capabilities = {
            player = { identity = { character = false, account = false, license = true }, job = false, duty = false },
            jobs = { multiple = false },
            money = { cash = false, bank = false },
            framework = { permissions = false }
        }
    }
}
local initialized = false
local function unsupported(feature) return nil, Errors.Create(Codes.UNSUPPORTED_FEATURE, 'Standalone mode does not provide this capability', { feature = feature, framework = 'standalone' }) end
function adapter.IsAvailable() return Config and (Config.Framework == 'standalone' or Config.FrameworkAutoStandalone == true) end
function adapter.Initialize() initialized = true; return true, nil end
function adapter.Shutdown() initialized = false; return true, nil end
function adapter.GetState() return initialized and 'HEALTHY' or 'UNAVAILABLE' end
function adapter.GetPlayer() return nil end
function adapter.IsPlayerLoaded() return false end
function adapter.GetCharacterIdentifier() return unsupported('player.identity.character') end
function adapter.GetAccountIdentifier() return unsupported('player.identity.account') end
function adapter.GetLicense(source)
    if not GetPlayerIdentifierByType then return unsupported('player.identity.license') end
    local value = GetPlayerIdentifierByType(tostring(source), 'license')
    if not value then return unsupported('player.identity.license') end
    return tostring(value), nil
end
function adapter.GetCharacterName() return unsupported('player.identity.character') end
function adapter.GetJob() return unsupported('player.job') end
function adapter.SubscribePlayerLoaded() return true, nil end
function adapter.SubscribePlayerUnloaded() return true, nil end
function adapter.SubscribeJobChanged() return true, nil end
function adapter.SubscribeDutyChanged() return true, nil end

function adapter.GetMoney(_, account) return nil, Errors.Create(Codes.UNSUPPORTED_ACCOUNT, 'Standalone mode has no money provider', { account = account }) end
function adapter.AddMoney(_, account) return false, Errors.Create(Codes.UNSUPPORTED_ACCOUNT, 'Standalone mode has no money provider', { account = account }) end
function adapter.RemoveMoney(_, account) return false, Errors.Create(Codes.UNSUPPORTED_ACCOUNT, 'Standalone mode has no money provider', { account = account }) end

NEXM_INTERNAL.Adapters.Framework.standalone = adapter
