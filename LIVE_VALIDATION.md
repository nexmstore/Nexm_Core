# NEXM Core 1.0.0-rc.1.hotfix.11 Live Validation

Status: **PENDING REAL FXSERVER USABLE-ITEM GATE**

Automated/offline coverage verifies the Core registry/adapter contracts, but real provider callback dispatch must still be exercised in FiveM.

Required live checks:

1. Full FXServer restart with hotfix.11.
2. Register one disposable usable item from a test consumer through `NEXM.Inventory.RegisterUsableItem`.
3. Verify source/context and confirm item count does not change merely from use.
4. Stop the consumer and verify the old callback cannot invoke its handler.
5. Restart/re-register the consumer and verify the new handler works.
6. Repeat on the validated profiles: A_ESX_OX, B_QB_QBINV, C_QB_OX, D_QBOX_OX, E_ESX_NATIVE.
7. On ox_inventory profiles, item definition must use `consume = 0` and `server.export = 'nexm_core.UseRegisteredItem'`.

Do not mark these live gates PASS until actual FXServer evidence is captured.
