local Resources = NEXM_INTERNAL.Managers.Resources
local Services = NEXM_INTERNAL.Managers.Services
local Features = NEXM_INTERNAL.Managers.Features
local Integrations = NEXM_INTERNAL.Managers.Integrations
local Migrations = NEXM_INTERNAL.Modules.Migrations
local Readiness = NEXM_INTERNAL.Modules.Readiness
local Lifecycle = NEXM_INTERNAL.Modules.Lifecycle
local EventBus = NEXM_INTERNAL.Modules.EventBus
local Permissions = NEXM_INTERNAL.Modules.Permissions
local Callbacks = NEXM_INTERNAL.Modules.Callbacks
local RateLimit = NEXM_INTERNAL.Modules.RateLimit
local Locale = NEXM_INTERNAL.Modules.Locale
local API = NEXM_INTERNAL.Modules.API
local State = NEXM_INTERNAL.Modules.State
local Logger = NEXM_INTERNAL.Modules.Logger
local States = NEXM_INTERNAL.Modules.Constants.STATES

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        State.Set(States.STOPPING)
        return
    end
    local removed = 0
    removed = removed + Resources.CleanupOwner(resourceName)
    removed = removed + Services.CleanupOwner(resourceName)
    removed = removed + Features.CleanupOwner(resourceName)
    removed = removed + Integrations.CleanupOwner(resourceName)
    removed = removed + Readiness.CleanupOwner(resourceName)
    removed = removed + Lifecycle.CleanupOwner(resourceName)
    if EventBus and EventBus.CleanupOwner then removed = removed + EventBus.CleanupOwner(resourceName) end
    if Permissions and Permissions.CleanupOwner then removed = removed + Permissions.CleanupOwner(resourceName) end
    if Callbacks and Callbacks.CleanupOwner then removed = removed + Callbacks.CleanupOwner(resourceName) end
    if RateLimit and RateLimit.CleanupOwner then removed = removed + RateLimit.CleanupOwner(resourceName) end
    if Locale and Locale.CleanupOwner then removed = removed + Locale.CleanupOwner(resourceName) end
    Migrations.CleanupOwner(resourceName)
    API.ClearFacade(resourceName)
    if removed > 0 then
        Logger.Info('Cleaned resource-owned registrations', { ownerResource = resourceName, removed = removed }, 'nexm_core')
    end
end)
