# Inventory

Inventory APIs are server-only. The canonical namespace is `NEXM.Inventory`.

Existing methods remain unchanged:

- `HasItem`
- `GetItemCount`
- `AddItem`
- `RemoveItem`
- `CanCarry`
- `GetItems`
- `RegisterUsableItem`

Inventory is independent of framework selection. Capability metadata includes `metadata`, `metadataFilter`, `canCarry`, `getItems`, and `usableItems`. Metadata is never silently discarded. If an adapter cannot accurately provide a capability, Core returns a structured error instead of silently switching to provider-specific gameplay code.

`Config.Inventory = 'none'` intentionally disables inventory without preventing Core READY. Inventory-dependent operations then fail with the normal Core inventory errors.

## RegisterUsableItem

```lua
local ok, err = NEXM.Inventory.RegisterUsableItem(itemName, handler, options)
```

This API is **server-side only** and is resource-owner bound. Core derives the registering resource from the public facade; the gameplay resource does not pass an owner name. A registration is stored as one canonical item → owner/handler record.

Example:

```lua
local ok, err = NEXM.Inventory.RegisterUsableItem(
    'example_workstation',
    function(source, item)
        -- item.name
        -- item.amount (currently 1 for a single use action)
        -- item.slot (provider-dependent, may be nil)
        -- item.metadata (provider-dependent, may be nil)
        -- item.provider
        -- Start gameplay flow here. Do not trust the client for item identity/source.
    end
)
```

Normalized handler context:

```lua
{
    name = 'example_workstation',
    amount = 1,
    slot = 7,          -- may be nil
    metadata = {},     -- may be nil
    provider = 'ox_inventory' -- or esx/qbcore/qbox
}
```

Registration returns `true, nil` on success. Validation/integration failures use Core's normal structured error object. Relevant canonical codes include `INVALID_ITEM`, `INVALID_HANDLER`, `ALREADY_REGISTERED`, `INVENTORY_UNAVAILABLE`, `FRAMEWORK_UNAVAILABLE`, `UNSUPPORTED_FEATURE`, and `INTEGRATION_ERROR`.

The same resource cannot silently duplicate its own registration, and another resource cannot silently replace the handler. `onResourceStop` removes that resource's registry entries. Where the underlying framework has no unregister API, its old callback wrapper may physically remain, but a generation guard prevents it from invoking a removed or newer gameplay handler.

For native framework registration, Core also checks the framework's supported usable-item lookup before binding (`ESX.GetUsableItems`, `QBCore.Functions.CanUseItem`, or `qbx_core:CanUseItem`). A pre-existing non-Core handler is rejected with `ALREADY_REGISTERED` instead of being silently overwritten.

### Item consumption

`RegisterUsableItem` **never removes or consumes the item**. It only begins the gameplay action. If an item should be consumed after an authoritative success, do it explicitly later:

```lua
local ok, err = NEXM.Inventory.RemoveItem(source, itemName, 1)
```

This is required for cancellable flows such as placement previews: cancelling with ESC/RMB/Backspace must leave the item in inventory.

## Provider behavior

### ESX native inventory

Core's ESX framework adapter registers the wrapper with `ESX.RegisterUsableItem`. The gameplay resource never imports ESX. ESX may not provide slot/metadata to the callback, so those normalized fields can be nil.

### QBCore + qb-inventory

Core's QBCore framework adapter uses `QBCore.Functions.CreateUseableItem`. The wrapper forwards the server-authoritative source and normalizes QB item slot/info metadata. The gameplay resource never imports QBCore or qb-inventory for registration.

### Qbox

Core includes the official Qbox `exports.qbx_core:CreateUseableItem` adapter path. In the supported Qbox + ox_inventory profile, usable items use the ox_inventory bridge below because the item use originates from ox_inventory. The gameplay resource still calls only `NEXM.Inventory.RegisterUsableItem`.

### ox_inventory

ox_inventory does not provide a runtime `RegisterUsableItem` API. NEXM Core therefore exposes one stable server export for ox item definitions:

```lua
['example_workstation'] = {
    label = 'Example Workstation',
    weight = 1000,
    stack = false,
    close = true,
    consume = 0,
    server = {
        export = 'nexm_core.UseRegisteredItem'
    }
}
```

Both `consume = 0` and the exact `server.export = 'nexm_core.UseRegisteredItem'` are required. Registration fails closed if the ox item definition is missing or misconfigured. The Core export accepts only ox_inventory's server-side item callback path, validates the invoking resource, derives player source from the authoritative player inventory, verifies the slot/item, then dispatches to the current Core registry entry. No client-supplied item name/source is trusted.

Because `consume = 0`, ox_inventory does not remove the item after a successful use callback. The gameplay resource retains explicit consumption control through Core.

## NEXM product rule

NEXM gameplay products must not directly call `ESX.RegisterUsableItem`, `QBCore.Functions.CreateUseableItem`, `exports.qbx_core:CreateUseableItem`, provider-internal events, or any invented ox_inventory usable-item registration API when NEXM Core provides this contract. Provider-specific item **definition/configuration** required by the inventory (such as the ox_inventory `server.export` field) remains server setup, not gameplay bridge code.
