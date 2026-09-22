# NEXM Core 1.0.0-rc.1.hotfix.3 Live Validation

Real-runtime validation is recorded separately from adapter availability. This document only claims the profiles explicitly confirmed as tested.

## Verified real-runtime profiles

| Profile | Stack | Status |
|---|---|---|
| A_ESX_OX | ESX + ox_inventory + ox_lib | **VERIFIED / LIVE TESTED** |
| B_QB_QBINV | QBCore + qb-inventory + QBCore notify | **VERIFIED / LIVE TESTED** |
| C_QB_OX | QBCore + ox_inventory + ox_lib | **VERIFIED / LIVE TESTED** |
| D_QBOX_OX | Qbox + ox_inventory + Qbox / ox_lib | **VERIFIED / LIVE TESTED** |
| E_ESX_NATIVE | ESX + ESX native inventory + ESX notify | **VERIFIED / LIVE TESTED** |

A_ESX_OX also has previously recorded detailed baseline evidence: FULL **159 PASS / 0 FAIL** followed by a real full FXServer restart and QUICK **120 PASS / 0 FAIL** on the functionally equivalent validated line. No equivalent numeric harness totals are asserted here for B/C/D/E because those totals were not supplied with the compatibility confirmation.

## Native NEXM Notify

`nexm_notify` v1.0.3 remains the recommended optional renderer and is integrated behind `NEXM.Notify.Send`. Its adapter/hot-restart contract is implemented. Separate live-certification evidence for the N_NATIVE_NOTIFY profile is not asserted by this matrix unless recorded independently.

## Operational contract

- `nexm_core` is not intended to be hot-restarted in production.
- Foundational framework/inventory changes should be applied with a full FXServer restart.
- After the Core build containing the adapter is installed, `nexm_notify` may be restarted independently.
