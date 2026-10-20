# NEXM Core Phase 4 — Economy & Inventory Layer

Phase 4 implements only server-side economy and inventory infrastructure. Notify, permissions, RPC, and gameplay systems remain out of scope.

## Public server API

Money:
- `NEXM.Money.Get(source, account)`
- `NEXM.Money.Add(source, account, amount, reason)`
- `NEXM.Money.Remove(source, account, amount, reason)`
- `NEXM.Money.CanAfford(source, account, amount)`

Canonical money accounts are only `cash` and `bank`.

Inventory:
- `NEXM.Inventory.HasItem(source, item, amount, metadata)`
- `NEXM.Inventory.GetItemCount(source, item, metadata)`
- `NEXM.Inventory.AddItem(source, item, amount, metadata)`
- `NEXM.Inventory.RemoveItem(source, item, amount, metadata)`
- `NEXM.Inventory.CanCarry(source, item, amount, metadata)`
- `NEXM.Inventory.GetItems(source)`

`GetItems` returns a minimal normalized view: `{ name, count, slot, metadata }`.

Money and Inventory are not exposed by the client facade and no generic client network mutation event exists.

## Framework money capability extension

The canonical framework capability contract now also requires:

```lua
money = {
    cash = true|false,
    bank = true|false
}
```

Missing fields are invalid. Explicit `false` is a valid unsupported declaration. Standalone declares both false. ESX, QBCore, and Qbox declare both true in the inspected versions.

Money mutations are validated as positive, finite integers bounded by `Config.Security.MaxMoneyTransaction`. Add/Remove require a bounded non-empty reason without control characters.

ESX account mappings: `cash -> money`, `bank -> bank`. QBCore and Qbox use `cash` / `bank` directly. ESX mutations are verified by authoritative pre/post balances because its xPlayer account mutation methods do not provide the same reliable boolean contract as QB/Qbox. QB/Qbox mutations also verify post-state, preventing Core from returning success merely because a mutation function was invoked.

## Inventory capability contract

Every inventory adapter declares all of:

```lua
capabilities = {
    metadata = boolean,
    metadataFilter = boolean,
    canCarry = boolean,
    getItems = boolean
}
```

All declarations are mandatory and inventory adapters must declare `critical=true`.

`metadata` means metadata can be supplied when creating an item. `metadataFilter` means query/removal can safely target the requested metadata variant. These capabilities are deliberately separate.

Metadata is a plain serializable Lua table. Core validates it and passes a deep copy to adapters. Core never silently drops metadata.

If metadata-filtered HasItem/GetItemCount/RemoveItem is requested on an adapter with `metadataFilter=false`, Core returns `UNSUPPORTED_FEATURE` with feature `inventory.metadataFilter`.

## Inventory adapters

### ox_inventory

Capabilities: metadata=true, metadataFilter=true, canCarry=true, getItems=true.

Uses strict metadata matching for count/removal and current server exports for GetItemCount, AddItem, RemoveItem, CanCarryItem, and GetInventoryItems.

### qb-inventory

Capabilities: metadata=true, metadataFilter=false, canCarry=true, getItems=true.

Current qb-inventory accepts `info` on AddItem, but its public count/remove flow is name/slot-oriented and does not provide a generic NEXM-safe metadata-filter contract. NEXM therefore refuses metadata-filtered query/removal instead of falling back to name-only removal.

### ESX native/default inventory

Capabilities: metadata=false, metadataFilter=false, canCarry=true, getItems=true.

The adapter is available only when `es_extended` is started and ESX does not report a custom inventory. Add/remove results are verified by authoritative pre/post counts.

### qs-inventory

Architecture implemented against Quasar's public documentation for GetInventory, AddItem, RemoveItem, and CanCarryItem, including documented metadata arguments. This adapter is documentation-verified only in this environment and is NOT claimed as real-server production-tested support.

### custom

`custom/inventory.lua` is editable and uses the exact same `InventoryContract` validator as built-in adapters. There is no bypass for custom integrations.

## Critical inventory selection and recovery

Inventory selection is independent of framework selection. `auto` with multiple available real candidates fails closed with `AMBIGUOUS_INVENTORY_INTEGRATION` unless an explicit administrator priority resolves it.

After successful selection the inventory backend is sticky. If it stops, inventory health becomes unavailable and public inventory calls fail with `INVENTORY_UNAVAILABLE`. Another installed inventory is not hot-selected. Only the same selected backend may recover after contract revalidation and reinitialization.

## Character-session safety

Sensitive Money and Inventory operations capture the Phase 3 `characterSessionId` before multi-step work and revalidate it before mutation and after backend calls. `Money.Remove` captures the session before its affordability read. `Inventory.AddItem` and `RemoveItem` keep the original session across CanCarry/count preflights.

Tests force character A -> B swaps during those intermediate reads and confirm the mutation backend is never reached for the stale operation. Current supported framework/inventory mutation APIs are treated as synchronous adapter calls; if a future adapter introduces an asynchronous mutation boundary it must preserve the same capture/revalidate rule before applying the delayed result.

## Upstream references inspected

- ESX Legacy: `esx-framework/esx_core`, commit `fe59ca0bd6da59e2ec6eb4a8d06ece312e96ae7a`, inspected manifest version `1.15.2`.
- QBCore: `qbcore-fivem/qb-core`, commit `9b3cddcce93e5e12cbcf6b47b866b687d32ac7bf`, inspected manifest version `1.3.0`.
- Qbox: `Qbox-project/qbx_core`, commit `c1c3ca16721cd14eb814cfb95e8f8631690d247d`, inspected manifest version `1.24.0`.
- ox_inventory: `overextended/ox_inventory`, commit `172b3914d0cf1967ead8cccc583763e8d5316eb7`, inspected manifest version `2.47.9`.
- qb-inventory: `qbcore-fivem/qb-inventory`, commit `a67334ff419dc7d94207317c8797faa6f2851d31`, inspected manifest version `2.1.0`.
- qs-inventory: current Quasar Store public Advanced Inventory export documentation inspected; no public source commit was treated as authoritative.

## Real FXServer validation

NOT EXECUTED in this environment. Before NEXM Core 1.0 production release, execute at minimum:

- ESX cash/bank get/add/remove/insufficient cases.
- QBCore cash/bank get/add/remove/insufficient cases.
- Qbox cash/bank get/add/remove/insufficient cases.
- ESX + ox_inventory.
- QBCore + ox_inventory.
- Qbox + ox_inventory.
- QBCore + qb-inventory.
- metadata A/B query and exact removal.
- full-inventory / capacity failures.
- character switch during economy/inventory workflows.
- Core restart with online players.
- selected inventory stop/same-backend recovery.
- selected framework stop/same-framework recovery.

## Performance

Phase 4 adds no money polling, inventory polling, per-player economy thread, or periodic inventory scan. Operations occur only on explicit API calls; runtime recovery uses resource lifecycle events. Idle overhead remains negligible.
