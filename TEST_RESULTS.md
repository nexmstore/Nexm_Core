# NEXM Core 1.0.0-rc.1.hotfix.11 Test Results

Build: `mvp_rc1_usable_items_4c3e8a71`

## Hotfix.11 usable-item coverage

- Core registry/ownership/dispatch spec: **16 PASS / 0 FAIL**
- ESX/QBCore/Qbox/ox_inventory adapter mocks: **18 PASS / 0 FAIL**
- Static architecture/security/provider audit: **37 PASS / 0 FAIL**
- Focused hotfix.11 total: **71 PASS / 0 FAIL**

Verified behavior includes valid registration, normalized source/context, no automatic item consumption, same-owner duplicate rejection, cross-resource collision rejection, external native-framework usable-handler collision rejection, owner cleanup, stale generation blocking, re-registration, invalid input errors, unsupported-profile fail-closed behavior, and the ox_inventory static server-export bridge.

## Existing regression suites

- hotfix.9 static DB/migration bridge regression: **21 PASS / 0 FAIL**
- hotfix.10 public DB restart-boundary static regression: **23 PASS / 0 FAIL**
- migration async model regression: **14 PASS / 0 FAIL**
- JS DB bridge model regression: **4 PASS / 0 FAIL**
- restart-boundary lifecycle model: **5 PASS / 0 FAIL**
- Existing regression total: **67 PASS / 0 FAIL**

Combined focused + existing automated assertions: **138 PASS / 0 FAIL**.

## Syntax / package architecture audits

- Lua `loadfile` syntax audit: **78 PASS / 0 FAIL**
- `server/db_bridge.js` JavaScript syntax: **PASS**
- fxmanifest local file entries: **75 present / 0 missing**
- usable-item load order: **PASS** (`inventory manager -> usable registry -> inventory domain -> public API`)
- baseline files removed: **0**
- existing six Inventory domain methods: **byte-equivalent after removing only additive usable-item wiring**
- existing public Inventory facade: **byte-equivalent after removing only the new method**
- FactoryWorks runtime code dependency/reference after stripping comments: **0**

## Preserved hotfix.10 / hotfix.9 invariants

The existing regression suite confirms the migration runner, internal DB implementation and JS DB bridge retain the established hotfix.9 behavior and the public DB restart-boundary behavior from hotfix.10 remains intact.

## Manual live gate still required

No real FXServer provider callback has been claimed as PASS for hotfix.11 yet. Live validation remains required on A_ESX_OX, B_QB_QBINV, C_QB_OX, D_QBOX_OX and E_ESX_NATIVE, including resource-stop/re-register behavior and confirming item count does not change on use alone.
