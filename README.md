# NEXM Core

NEXM Core is a free, server-first FiveM infrastructure SDK for NEXM products. It normalizes framework/player lifecycle, money, inventory, RPC/security, notifications, localization, audit, services, integrations, components, migrations and diagnostics so NEXM products can target one stable Core contract.

**Release candidate:** `1.0.0-rc.1.hotfix.4`  
**Internal build:** `mvp_rc1_tempappearance_7f2c4a91`  
**Release scope:** `MVP_RC_TEMP_APPEARANCE_RECOVERY`

This RC keeps the validated framework/inventory matrix and adds one reusable infrastructure capability: restart-safe Temporary Appearance Recovery for NEXM-controlled temporary outfits. It is not a clothing/character system and does **not** claim to be final `1.0.0`.

## Validated compatibility matrix

The following real-runtime profiles are verified:

- A_ESX_OX — ESX + ox_inventory + ox_lib
- B_QB_QBINV — QBCore + qb-inventory + QBCore notify
- C_QB_OX — QBCore + ox_inventory + ox_lib
- D_QBOX_OX — Qbox + ox_inventory + Qbox / ox_lib notify
- E_ESX_NATIVE — ESX + ESX native inventory + ESX notify

Framework adapters included: ESX, QBCore, Qbox. Inventory adapters included: ox_inventory, qb-inventory, ESX native inventory, plus qs-inventory adapter architecture. Notification providers include NEXM Notify v1.0.3 (recommended), ox_lib, ESX, QBCore, Qbox, and custom where implemented.

The five profiles above are release-validated. NEXM Notify is supported and recommended, but this package does not claim separate live-certification evidence for the N_NATIVE_NOTIFY profile unless that test evidence is recorded independently.


## Temporary Appearance Recovery

Core now provides resource-owner-bound persistent recovery records for temporary outfits. Server consumers use `NEXM.TemporaryAppearance.Save/Get/Has/Clear/AcknowledgeRestore`; client consumers may use `NEXM.TemporaryAppearance.Capture/Restore/Verify`. Records are keyed by Core's canonical player identity and consumer resource owner, persisted in `data/temporary_appearances.json`, and are not cleared on disconnect. A verified restore acknowledgement is required before normal cleanup. See `docs/temporary-appearance.md`.

## Install

1. Install `oxmysql` and the framework/integrations required by the products using Core.
2. Put `nexm_core` in the server resources directory.
3. Configure `config.lua` and any customer-owned custom adapters.
4. Ensure `oxmysql`, the selected framework and required integrations before `nexm_core`; start NEXM products after Core.
5. Run `nexm:status` from the server console.

Every NEXM consumer resource must load `@nexm_core/import.lua` as a **shared script** before its own scripts, then acquire Core with `exports['nexm_core']:GetCoreObject()`.

Core READY means platform initialization succeeded. Product resources declare their own framework/inventory/notify requirements.

See `docs/installation.md`, `docs/creating-nexm-resource.md`, `API_FREEZE.md`, `NETWORK_SURFACE.md`, `docs/security.md`, `COMPATIBILITY.md`, and `LIVE_VALIDATION.md`.
