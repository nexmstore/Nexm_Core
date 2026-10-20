# NEXM Core Phase 2–7 tests

## Automated runners

- `phase2_regression_runner.lua` — complete foundation regression and current bootstrap ordering.
- `phase3_runner.lua` — Framework/Player/Jobs/lifecycle/multichar/session regression.
- `phase4_runner.lua` — Money/Inventory contracts, metadata safety, integration recovery and session races.
- `phase5_runner.lua` — component readiness/requirements, RPC, internal events, permissions, rate limiting, ownership and networking security.
- `phase6_runner.lua` — notifications, localization, audit, logger safety, services API versions, component/integration diagnostics, docs and Phase 5 surface-separation checks.
- `phase7_runner.lua` — pre-RC version/config validation, public API freeze, export/network surface, client-security/privacy/manifest/package and live-profile release audits.

Final automated result after Phase 7 hardening:

- Phase 2: **76 / 76 PASS**
- Phase 3: **155 / 155 PASS**
- Phase 4: **176 / 176 PASS**
- Phase 5: **144 / 144 PASS**
- Phase 6: **142 / 142 PASS**
- Phase 7: **103 / 103 PASS**
- Total: **796 / 796 PASS**
- Failures: **0**

The harness stubs FiveM/framework/inventory/oxmysql/network/HTTP globals. Harness results are not real FXServer PASS results.

## Real FXServer status

**NOT EXECUTED / BLOCKED** in this environment. See `live/README.md` and root `LIVE_VALIDATION.md`.

Before NEXM Core 1.0 production release, retain all Phase 3–5 live checks and add Phase 6:

### Notifications
1. ox_lib notify: all four normalized types.
2. ESX native/esx_notify mapping.
3. QBCore mapping (`info` → native primary).
4. Qbox native Notify mapping (`info` → inform).
5. normalized server→client notify event.
6. local client `NEXM.Notify.Send`.
7. `Notify=none`, auto/no provider, fallback enabled/disabled.
8. provider stop/recovery and sticky-primary resume.

### Localization
1. shared product locale registration visible in server and client runtimes.
2. requested locale lookup and resource fallback.
3. missing locale → English → key behavior.
4. interpolation and resource restart cleanup/re-registration.

### Audit/logging
1. database `nexm_audit_log` creation and inserts.
2. database outage/recovery without gameplay rollback.
3. Discord webhook success, HTTP failure, retries and queue pressure.
4. verify webhook privacy defaults omit technical identifiers.
5. custom backend success/failure.
6. log level and repeated-warning suppression in real console output.

### Developer/runtime lifecycle
1. service owner stop/restart and API version checks.
2. `nexm:status` and `nexm:status verbose` throughout component transitions.
3. Core restart with players/resources present.
4. rerun actual-client Phase 5 RPC/permission/rate/stale-session tests with Phase 6 installed.
