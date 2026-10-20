# NEXM Core build metadata

- Public version: `1.0.0-rc.1.hotfix.11`
- Internal build id: `mvp_rc1_usable_items_4c3e8a71`
- Base: `1.0.0-rc.1.hotfix.10`
- Change type: backwards-compatible server API addition
- New public API: `NEXM.Inventory.RegisterUsableItem(itemName, handler, options?)`
- Ownership: automatically bound to the registering resource
- Consumption: never automatic; gameplay code explicitly calls existing `RemoveItem` only after success
- Official provider paths: ESX native, QBCore + qb-inventory, Qbox + ox_inventory, QBCore/ESX + ox_inventory through the stable Core ox server-export bridge
- Unsupported provider combinations: fail closed with Core structured errors
- hotfix.10 public DB restart-boundary implementation: retained
- Internal DB/migration implementation and historical checksums: unchanged
- FactoryWorks dependency: none; no FactoryWorks-specific item names or logic are present in Core runtime source
