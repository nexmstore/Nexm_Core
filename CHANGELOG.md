# 1.0.0-rc.1.hotfix.11

- Added resource-owner-bound server API `NEXM.Inventory.RegisterUsableItem(itemName, handler, options?)`.
- Added canonical usable-item registry, duplicate/cross-resource collision protection, owner cleanup and stale framework callback generation guards.
- Added normalized item context and explicit non-consumption semantics.
- Added ESX, QBCore and Qbox framework registration adapters plus the documented ox_inventory stable server-export bridge.
- Added `usableItems` capability declarations and fail-closed `UNSUPPORTED_FEATURE` behavior for unsupported integration paths.
- Preserved all existing inventory APIs and hotfix.10 DB/restart behavior.

# 1.0.0-rc.1.hotfix.10

- Fixed the remaining dependent-resource restart function-reference error by proxying public server `NEXM.DB.*` calls through local request/result events.
- On resource stop, Core cancels pending public DB transport ownership and never attempts to return a completed async DB result into the destroyed caller environment.
- Preserved the public DB API, internal JS DB bridge, migration runner, migration SQL/checksums, and FactoryWorks unchanged.
- Added restart-boundary regression coverage for orphaning an old in-flight DB result while allowing a new resource instance to continue normally.

# 1.0.0-rc.1.hotfix.9

- Replaced the Core Lua→oxmysql callback path with a Core-owned JavaScript DB bridge using oxmysql `*_async` exports.
- Removed the temporary hotfix.7/8 migration-specific request/result proxy; `Migrations.Run()` again uses the generic Core facade transport.
- Preserved structured fail-closed DB errors, migration checksums, duplicate-run protection and `cleanupPending`.
- No FactoryWorks migration SQL/checksum/schema changes.

# 1.0.0-rc.1.hotfix.8

- Deferred Core DB promise resolution to the next server tick instead of resuming `Citizen.Await` continuations synchronously from inside the oxmysql/CFX callback.
- Deferred the consumer-side migration-result promise resume for the same boundary-safety reason.
- Preserved the hotfix.7 server-local migration proxy, checksum validation, duplicate-run guard, cleanupPending, and fail-closed DB behavior.
- No FactoryWorks migration SQL/checksum or schema changes.

# 1.0.0-rc.1.hotfix.6

- Removed broad `xpcall` from the yielding migration runner.
- Removed `pcall(Citizen.Await, ...)` from the oxmysql callback wrapper.
- Preserved fail-closed migration errors, checksum protection, duplicate-run guard and deferred cleanup.
- No product migration definitions/checksums changed.

# Changelog

## 1.0.0-rc.1.hotfix.6 — DB sparse-parameter + migration fail-closed hardening

- Core DB wrapper now normalizes sparse positional Lua parameter tables before crossing into oxmysql. Interior `nil` slots are emitted as SQL `NULL` while remaining parameters are compacted into a dense array.
- Malformed sparse parameter shapes fail closed with `DATABASE_INVALID_PARAMS` instead of reaching `rawQuery`.
- Transaction query descriptors receive the same normalization.
- Migration runner now validates tracking query result shape, guards concurrent duplicate runs, preserves checksum validation, and converts unexpected runner failures into structured `MIGRATION_ERROR`.
- Optional migration diagnostics are available through `set nexm_debug_migrations 1` (or `Config.Debug=true`) and do not print parameter values.
- No existing migration definition or checksum algorithm was changed.

## 1.0.0-rc.1.hotfix.4 — temporary appearance recovery

- Adds generic restart-safe Temporary Appearance Recovery infrastructure.
- Persists native ped model/components/props per canonical player identity + resource owner in JSON.
- Prevents duplicate saves from overwriting the original civilian snapshot by default.
- Adds resource-bound server API: `TemporaryAppearance.Save/Get/Has/Clear/AcknowledgeRestore`.
- Adds native client helpers: `TemporaryAppearance.Capture/Restore/Verify`.
- Keeps records across disconnects and clears only after explicit verified-restore acknowledgement.
- Adds staged/backup persistence recovery and corrupt/missing-file fail-safe handling.
- Adds `/nexmtempappearance` debug summary when `Config.Debug=true`.
- No framework clothing dependency or SQL migration added.

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
