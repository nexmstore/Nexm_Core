# Client API

Load `@nexm_core/import.lua` as a `shared_script` in the consumer fxmanifest before client scripts. This is the canonical NEXM loader and must execute in the consumer client runtime.

Client:

```lua
local NEXM = exports['nexm_core']:GetCoreObject()
```

Available client namespaces are intentionally limited: `Player` local snapshot helpers, `Callback.Await`, `Notify.Send`, `Locale`, lifecycle `Events`, `Validate`, and `Version`.

There is no client `Money`, `Inventory`, `Permissions`, `Audit`, or `RateLimit` namespace. Client code is untrusted; authorization and sensitive mutations belong on the server.
