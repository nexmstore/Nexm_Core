# Installation

Place `nexm_core` in the server resources directory. `oxmysql` is a Core dependency and must start before Core. Start the selected framework before Core where framework functionality is required. Start inventory/notify providers required by your product profile before dependent NEXM products.

Example A_ESX_OX order:

```cfg
ensure oxmysql
ensure ox_lib
ensure es_extended
ensure ox_inventory
ensure nexm_core
ensure <nexm_product>
```

Use `nexm:status` after startup and `nexm:status verbose` for capability/resource-requirement diagnostics. For A_ESX_OX, changes to `es_extended`, `ox_inventory` or `ox_lib` are applied with a full FXServer restart; individual dependency hot restart is not part of the supported release contract.

## Consumer transport shim

Every NEXM product must load `@nexm_core/import.lua` as a **shared script** before its own shared/server/client scripts:

```lua
shared_script '@nexm_core/import.lua'
```

The public acquisition syntax remains:

```lua
local NEXM = exports['nexm_core']:GetCoreObject()
```

`nexm_core` ships `import.lua` in its client packfile so the same loader executes in both server and client consumer runtimes. Detailed transport/import diagnostics are off in normal operation and are enabled only when `nexm_debug_transport=1` is explicitly set for troubleshooting.
