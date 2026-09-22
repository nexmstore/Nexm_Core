# Changelog

## 1.0.0-rc.1.hotfix.3 — validated compatibility matrix

- Marks A_ESX_OX, B_QB_QBINV, C_QB_OX, D_QBOX_OX and E_ESX_NATIVE as verified/live tested based on completed real-runtime validation.
- Updates release scope from single-profile MVP validation to the verified compatibility matrix.
- Bumps release/build identity so runtime diagnostics and consumer import fingerprints match the packaged artifact.
- No runtime adapter logic, DB schema, migration, gameplay or public API changes from hotfix.2.
- NEXM Notify remains supported/recommended; separate N_NATIVE_NOTIFY live-certification is not claimed without its own recorded evidence.

## 1.0.0-rc.1.hotfix.2 — native NEXM Notify provider

- Adds `nexm_notify` v1.0.3 as an official optional notification provider without changing `NEXM.Notify.Send`.
- Makes the native NEXM renderer the shipped production/default priority, with existing providers retained as fallback options.
- Uses direct `nexm_notify:notify` server→client dispatch for server notifications and the live client export for client notifications.
- Re-checks resource availability at dispatch time; `restart nexm_notify` does not require restarting `nexm_core`.
- Normalizes NEXM Notify renderer-specific title/message/duration limits at the provider boundary only.
- Adds verbose notify provider/resource/state/fallback diagnostics.
- No DB schema, migration, framework, inventory, money, permission, RPC, or public Notify API changes.


## 1.0.0-rc.1.hotfix.1 — callback return transport hotfix

- Preserves cross-resource callback handler `nil, err` tuples through the Cfx function-reference boundary.
- Decodes consumer callback return envelopes before Core RPC error/response handling.
- No DB schema, migration, framework, inventory, money, permission, or gameplay contract changes.


## 1.0.0-rc.1 — MVP release candidate

- Retains the validated Fix9 client-import transport fix and canonical consumer facade; internal RC fingerprint is `mvp_rc1_c325815e`.
- Feature freeze: no new gameplay or major public namespaces.
- Promoted the validated development line to explicit `1.0.0-rc.1`; final `1.0.0` remains separately gated.
- Expanded startup configuration validation for locale, log level, notify limits, RPC/network bounds, security limits, and audit queue/backend settings.
- Added release/API/network/client-security inventories.
- Added isolated live-test resource and environment profiles.
- Added release/upgrade/compatibility/known-limitations documentation.
- Added Phase 7 automated release-hardening regression.
- RC cleanup gates normal import/transport status noise behind the existing diagnostic convar; public RPC/transport behavior is unchanged.

## Phase 6 approved baseline

Feature-complete platform services and developer experience. Automated baseline: 693/693 assertions PASS before Phase 7 hardening.
