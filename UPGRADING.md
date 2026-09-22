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
