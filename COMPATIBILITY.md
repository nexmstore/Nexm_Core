# Compatibility Matrix

The compatibility profiles below have been validated in a real FiveM runtime environment. Adapter inclusion and live validation are still tracked separately for integrations that are not part of the verified matrix.

| Profile | Framework | Inventory | Notify | RC live status |
|---|---|---|---|---|
| A_ESX_OX | ESX | ox_inventory | ox_lib | **VERIFIED / LIVE TESTED** |
| B_QB_QBINV | QBCore | qb-inventory | QBCore | **VERIFIED / LIVE TESTED** |
| C_QB_OX | QBCore | ox_inventory | ox_lib | **VERIFIED / LIVE TESTED** |
| D_QBOX_OX | Qbox | ox_inventory | Qbox / ox_lib | **VERIFIED / LIVE TESTED** |
| E_ESX_NATIVE | ESX | ESX native | ESX | **VERIFIED / LIVE TESTED** |
| N_NATIVE_NOTIFY | Any supported framework | Any supported inventory | nexm_notify v1.0.3 | **SUPPORTED / RECOMMENDED; separate live-certification evidence not recorded in this matrix** |

## Verified framework coverage

- ESX: verified with ox_inventory + ox_lib and with ESX native inventory + ESX notify.
- QBCore: verified with qb-inventory + QBCore notify and with ox_inventory + ox_lib.
- Qbox: verified with ox_inventory + Qbox / ox_lib notify configuration.

## Inventory capability notes

- `qb-inventory` intentionally reports no metadata-filtering support in the Core capability contract.
- ESX native inventory does not claim modern metadata-filtering semantics.
- `qs-inventory` has adapter architecture but is not included in the verified matrix above.

## Restart contract

Foundational framework/inventory dependency changes are applied with a full FXServer restart. `nexm_core` is not intended to be hot-restarted in production.

`nexm_notify` is an optional renderer integration and may be restarted independently after the Core version containing its adapter has been installed with a full FXServer restart.
