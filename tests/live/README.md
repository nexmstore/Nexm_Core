# NEXM Core Phase 7 Live Test Harness

This directory is **not loaded by the production manifest**. It is a developer-only resource/checklist for real FXServer validation. Never install it on a production server.

Status vocabulary is strict: `PASS`, `FAIL`, `NOT EXECUTED`, `BLOCKED`. Record exact FXServer artifact, OS, DB/version, oxmysql version, framework commit/version, inventory version, notify provider/version, OneSync mode, slots and the NEXM artifact hash before each run.

## Minimum profiles

- A: ESX Legacy + oxmysql + supported inventory/notify
- B: QBCore + qb-inventory + oxmysql
- C: QBCore + ox_inventory + oxmysql
- D: Qbox + ox_inventory + oxmysql
- E: ESX native inventory when practical
- QS: only with a legitimate installation/runtime

## Live sequence

1. Startup/order/status/verbose status.
2. DB wrapper + migrations + restart/checksum behavior.
3. Real player identity/job/duty/multicharacter.
4. Core/framework/inventory restart and repeated restart cycles.
5. Money matrix and invalid mutation inputs.
6. Inventory and metadata safety matrix.
7. Character-switch race tests using this test resource, never production Core hooks.
8. Real RPC/timeout/duplicate/spam/payload limits.
9. Job/ACE/framework permissions.
10. Internal EventBus across two server resources.
11. Visible notify and fallback.
12. Server/client locale.
13. Audit DB/Discord/outage/queue pressure.
14. Ownership/service/requirements/components/status.
15. Resmon/CPU/memory and soak/restart cycles.

Detailed abuse mechanics should remain in controlled developer test notes, not customer-facing documentation.
