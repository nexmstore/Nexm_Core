# Upgrading to 1.0.0-rc.1

1. Back up `config.lua` and the database.
2. Stop dependent NEXM product resources.
3. Replace the `nexm_core` resource files.
4. Merge configuration deliberately; do not overwrite custom adapter implementations blindly.
5. Ensure `oxmysql`, the selected framework and required integrations before Core/products.
6. Start Core and run `nexm:status verbose`.
7. Start dependent products and verify their requirement state.

No schema reset is part of this release candidate. Applied migrations remain immutable and historical checksum mismatches remain fatal.

For A_ESX_OX dependency changes, use a full FXServer restart rather than individually hot-restarting `es_extended`, `ox_inventory`, or `ox_lib`.

## Upgrade to 1.0.0-rc.1.hotfix.2

Perform one full FXServer restart when replacing the Core so all consumers reload `@nexm_core/import.lua` with build `mvp_rc1_nexmnotify_04c86745`. After that, `nexm_notify` may be restarted independently without restarting Core. Existing notification renderers remain available as fallback providers when configured.


## Upgrade to 1.0.0-rc.1.hotfix.3

This is a release-metadata/certification update over hotfix.2. Runtime behavior is unchanged. Replace the resource and perform a full FXServer restart so consumers reload `@nexm_core/import.lua` with build `mvp_rc1_matrix_13401539`.

## Upgrade to 1.0.0-rc.1.hotfix.6

Replace the Core resource and perform a **full FXServer restart** so all consumers reload `@nexm_core/import.lua` with build `mvp_rc1_migration_boundary_b612f3a0`. This build changes the shared migration/DB coroutine boundary; restarting only `nexm_factoryworks` is not sufficient to load the new Core.

Preserve `data/temporary_appearances.json` if it contains pending recovery records. Do not edit/delete `nexm_migrations`, recalculate historical checksums, or change FactoryWorks migrations for this hotfix.

## Upgrade to 1.0.0-rc.1.hotfix.10

Hotfix.10 adds a server-local public DB transport proxy so dependent resource restarts cannot leave a yielding Core function-reference return targeting a destroyed caller environment. Public `NEXM.DB.*` and `NEXM.Migrations.*` signatures remain unchanged. Replace the full `nexm_core` resource and perform a **FULL FXServer restart** so every consumer reloads `@nexm_core/import.lua` build `mvp_rc1_public_db_proxy_a41f5e90`. Preserve `data/temporary_appearances.json` and do not modify historical migrations/checksums.


## Upgrade to 1.0.0-rc.1.hotfix.11

Replace the full `nexm_core` resource and perform a **FULL FXServer restart** so every consumer reloads `@nexm_core/import.lua` build `mvp_rc1_usable_items_4c3e8a71`. Existing public APIs remain compatible.

Products that adopt `NEXM.Inventory.RegisterUsableItem` must remove their direct framework usable-item registration code. For ox_inventory, define each usable item with `consume = 0` and `server.export = 'nexm_core.UseRegisteredItem'`. Do not add a direct ox_inventory bridge inside the gameplay product. Preserve `data/temporary_appearances.json` and historical migration records/checksums.
