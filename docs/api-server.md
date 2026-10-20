# Server API

Load `@nexm_core/import.lua` in the consumer fxmanifest, then obtain the resource-bound facade:

```lua
local NEXM = exports['nexm_core']:GetCoreObject()
```

Server namespaces implemented in Phase 6:

`Player`, `TemporaryAppearance`, `Jobs`, `Money`, `Inventory`, `Notify`, `Permissions`, `Callback`, `Events`, `Locale`, `Log`, `Audit`, `Validate`, `RateLimit`, `Resources`, `Services`, `Features`, `Integrations`, `Components`, `Version`, `DB`, `Migrations`.

Mutation methods generally return `boolean, err`; getters return `value, err`; predicates return `boolean, err`. Errors are structured `{ code, message, context }` objects. See the topic documents for capability and lifecycle requirements.


## TemporaryAppearance

The server namespace is bound to the calling resource. Consumers do not pass a player identifier or another resource owner. Core derives the canonical player identity from `source` and uses the consumer resource name as the owner key.

```lua
local ok, result = NEXM.TemporaryAppearance.Save(source, snapshot)
local record, err = NEXM.TemporaryAppearance.Get(source)
local has, err = NEXM.TemporaryAppearance.Has(source)
local ok, err = NEXM.TemporaryAppearance.AcknowledgeRestore(source)
```

`Save` preserves an existing record by default, so a retry while the player is already wearing a temporary outfit cannot overwrite the original civilian snapshot. `options.force=true` exists only for trusted server-side recovery/admin logic. `Clear`/`AcknowledgeRestore` affect only the calling resource's owner record.

## Inventory.RegisterUsableItem

```lua
local ok, err = NEXM.Inventory.RegisterUsableItem(itemName, function(source, itemContext)
    -- server gameplay handler
end, options)
```

This registration is bound automatically to the calling resource and is cleaned from Core's registry when that resource stops. The handler receives normalized `{ name, amount, slot, metadata, provider }` context. Registration does not consume the item; explicit server-side `NEXM.Inventory.RemoveItem` remains the gameplay resource's responsibility after its own success condition. See `docs/inventory.md` for ESX, QBCore, Qbox and ox_inventory setup.
