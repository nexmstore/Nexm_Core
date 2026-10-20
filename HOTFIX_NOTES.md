# NEXM Core 1.0.0-rc.1.hotfix.11

Build: `mvp_rc1_usable_items_4c3e8a71`

## Added

`NEXM.Inventory.RegisterUsableItem(itemName, handler, options?)` is a resource-owner-bound server API. Core stores one active handler per item, rejects collisions, removes owner registrations on resource stop, and guards framework callbacks with generation tokens so stale wrappers cannot invoke removed/replaced gameplay handlers.

The handler receives normalized server context: item name, amount, optional slot, optional metadata and provider name. No item is removed automatically.

## Provider paths

- ESX: `ESX.RegisterUsableItem` inside the framework adapter.
- QBCore: `QBCore.Functions.CreateUseableItem` inside the framework adapter.
- Qbox: official `exports.qbx_core:CreateUseableItem` adapter support.
- ox_inventory: static item `server.export = 'nexm_core.UseRegisteredItem'` with `consume = 0`; the stable Core export validates the ox server callback and dispatches to the current owner registry.

Native framework adapters preflight existing usable-item registrations where the official lookup API exists and return `ALREADY_REGISTERED` rather than silently overwriting a handler owned outside Core.

No undocumented ox_inventory events are used, and there is no global client "use item" event.
