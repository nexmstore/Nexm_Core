# NEXM Core 1.0.0-rc.1.hotfix.3 — Automated Regression and Live Qualification

## Offline automated regression baseline

The established RC regression baseline remains:

- Phase 2 regression suites: **76 / 76 PASS**
- Phase 3: **179 / 179 PASS**
- Phase 4: **176 / 176 PASS**
- Phase 5: **144 / 144 PASS**
- Phase 6: **142 / 142 PASS**
- Phase 7 release hardening/RC cleanup: **209 / 209 PASS**
- **TOTAL: 926 / 926 PASS, 0 FAIL**
- Production/test Lua syntax scan baseline: **85 files checked, 0 failures**

Validator offline regression baseline: `nexm_core_test` 0.1.8 self-tests **92 / 92 PASS, 0 FAIL**.

## Real-runtime compatibility qualification

The following profiles are confirmed verified/live tested:

- A_ESX_OX — ESX + ox_inventory + ox_lib
- B_QB_QBINV — QBCore + qb-inventory + QBCore notify
- C_QB_OX — QBCore + ox_inventory + ox_lib
- D_QBOX_OX — Qbox + ox_inventory + Qbox / ox_lib
- E_ESX_NATIVE — ESX + ESX native inventory + ESX notify

A_ESX_OX has previously recorded detailed harness evidence: FULL **159 PASS / 0 FAIL** and post-reboot QUICK **120 PASS / 0 FAIL**. The compatibility confirmation for the remaining profiles establishes real-runtime functional verification but does not provide numeric harness totals, so none are invented here.

## 1.0.0-rc.1.hotfix.3 certification-metadata update

Build: `mvp_rc1_matrix_13401539`

This update changes only release/build identity and documentation/status metadata for the verified compatibility matrix. Runtime provider/adaptor logic is unchanged from hotfix.2. Package integrity and manifest/reference checks are rerun for the generated ZIP.

`nexm_notify` v1.0.3 remains supported/recommended, but separate N_NATIVE_NOTIFY live-certification is not claimed in this document without explicit evidence.
