# Client API

Load `@nexm_core/import.lua` as a `shared_script` in the consumer fxmanifest before client scripts. This is the canonical NEXM loader and must execute in the consumer client runtime.

Client:

```lua
local NEXM = exports['nexm_core']:GetCoreObject()
```

Available client namespaces are intentionally limited: `Player` local snapshot helpers, `Callback.Await`, `Notify.Send`, `TemporaryAppearance` native ped snapshot helpers, `Locale`, lifecycle `Events`, `Validate`, and `Version`.

There is no client `Money`, `Inventory`, `Permissions`, `Audit`, or `RateLimit` namespace. Client code is untrusted; authorization and sensitive mutations belong on the server.


## TemporaryAppearance

```lua
local snapshot, err = NEXM.TemporaryAppearance.Capture()
local ok, err = NEXM.TemporaryAppearance.Restore(snapshot)
local verified, err = NEXM.TemporaryAppearance.Verify(snapshot)
```

The helper captures model, component 0-11 drawable/texture/palette values and prop 0-7 drawable/texture values. If the model differs during restore, behavior follows `Config.TemporaryAppearance.restoreModel`; a failed verification must not be acknowledged to the server.
