# NEXM Core Phase 7 — Release Hardening Notes

## Status

Feature development is frozen. Current build is `1.0.0-dev.7` with release status `PRE_RC_UNVALIDATED`. It is not `1.0.0-rc.1` and not final `1.0.0`.

## Automated hardening

Phase 7 adds release-only hardening: stronger startup config validation, public API freeze inventory, network/export surface inventory, client-security inventory, release/upgrade/compatibility documentation, developer-only live test profiles/resource, manifest escrow editability and packaging/security checks. No gameplay or major public API was added.

## Real-runtime provisioning result

Real FXServer validation is blocked in this execution workspace. The host has no provisioned Cfx server license key, real FiveM/GTA client, MySQL/MariaDB service, ESX/QBCore/Qbox runtime profiles, or dedicated Discord test webhook. A direct attempt to fetch the official Linux FXServer artifact from the container also failed because the container runtime cannot resolve external hosts.

Therefore mandatory environments A-D and all real-client scenarios remain `NOT EXECUTED`/`BLOCKED`. Harness PASS results are not substituted for live PASS.

## Release gate

`1.0.0-rc.1` remains blocked until mandatory environments A-D have actual live results and no release blocker is known.
