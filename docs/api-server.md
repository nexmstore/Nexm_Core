# Server API

Load `@nexm_core/import.lua` in the consumer fxmanifest, then obtain the resource-bound facade:

```lua
local NEXM = exports['nexm_core']:GetCoreObject()
```

Server namespaces implemented in Phase 6:

`Player`, `Jobs`, `Money`, `Inventory`, `Notify`, `Permissions`, `Callback`, `Events`, `Locale`, `Log`, `Audit`, `Validate`, `RateLimit`, `Resources`, `Services`, `Features`, `Integrations`, `Components`, `Version`, `DB`, `Migrations`.

Mutation methods generally return `boolean, err`; getters return `value, err`; predicates return `boolean, err`. Errors are structured `{ code, message, context }` objects. See the topic documents for capability and lifecycle requirements.
