# Creating a NEXM Resource

A product depends on NEXM Core and uses only the stable NEXM facade. Load `@nexm_core/import.lua` as a shared script before product scripts; this preserves Lua `value, err` / `nil, err` return tuples across real Cfx resource boundaries while keeping the canonical `GetCoreObject()` syntax unchanged.

## fxmanifest.lua

```lua
fx_version 'cerulean'
game 'gta5'
dependency 'nexm_core'
shared_script '@nexm_core/import.lua'
shared_script 'shared/locales.lua'
server_script 'server/main.lua'
client_script 'client/main.lua'
```

## shared/locales.lua

```lua
local NEXM = exports['nexm_core']:GetCoreObject()
NEXM.Locale.Register('en', { hello = 'Hello, {name}' })
NEXM.Locale.Register('lt', { hello = 'Labas, {name}' })
```

## server/main.lua

```lua
local NEXM = exports['nexm_core']:GetCoreObject()

local ok, err = NEXM.Resources.Register({
    name = 'nexm_example',
    version = '1.0.0',
    requiresCore = '>=1.0.0-0', -- pre-release validation; use >=1.0.0 for final
    requirements = {
        framework = true,
        frameworkCapabilities = { 'money.cash' },
        integrations = {
            inventory = { required = false }
        }
    }
})
if not ok then error(err.message) end

NEXM.Permissions.Define('manage', {
    mode = 'any',
    jobs = { police = { minimumGrade = 3 } }
})

NEXM.Callback.Register('getData', function(source, payload, context)
    NEXM.Log.Info('Example data requested', { source = source })
    NEXM.Audit.Log({ action = 'data_requested', actor = source })
    return { message = NEXM.Locale.Get('hello', { name = NEXM.Player.GetCharacterName(source) }) }
end, { permission = 'manage', requireCharacter = true })

NEXM.Events.On('example:changed', function(payload)
    NEXM.Log.Debug('Example changed', payload)
end)

NEXM.Services.Register('example', {
    Ping = function() return true end
}, { version = '1.0.0', apiVersion = 1 })

-- Sensitive gameplay operations stay server-side.
-- local ok = NEXM.Money.CanAfford(source, 'cash', 100)
-- local count = NEXM.Inventory.GetItemCount(source, 'example_item')
```

## client/main.lua

```lua
local NEXM = exports['nexm_core']:GetCoreObject()
local data, err = NEXM.Callback.Await('getData', {})
if data then NEXM.Notify.Send(data.message, 'info', 5000) end
```

Resource-owned callbacks, permissions, services, locales and listeners are cleaned automatically when the resource stops. Register again normally after a development restart. A product should declare every component/capability it depends on and fail closed when the requirement is unavailable.
