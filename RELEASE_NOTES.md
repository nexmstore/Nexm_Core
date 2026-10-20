# NEXM Core 1.0.0-rc.1.hotfix.11 — Universal Usable Item API

- Public version: `1.0.0-rc.1.hotfix.11`
- Internal build: `mvp_rc1_usable_items_4c3e8a71`

Hotfix.11 adds the canonical server-side `NEXM.Inventory.RegisterUsableItem(itemName, handler, options?)` API. NEXM gameplay resources can now register item-use actions without importing ESX, QBCore, Qbox, ox_inventory or qb-inventory directly.

Core owns registration, provider dispatch, normalized item context, resource ownership/collision checks, stale-callback protection and resource-stop cleanup. Registration never consumes an item automatically. Existing `HasItem`, `GetItemCount`, `AddItem`, `RemoveItem`, `CanCarry` and `GetItems` contracts are unchanged.

Provider handling uses the official framework APIs for ESX/QBCore/Qbox and a stable `nexm_core.UseRegisteredItem` server export for ox_inventory static item definitions with `consume = 0`. Unsupported paths fail closed instead of using undocumented events or provider hacks.

This release is based on hotfix.10 and retains its public DB restart-boundary protections and prior migration/database fixes.
