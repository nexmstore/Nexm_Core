# Known Limitations

- This is still a release-candidate line, not final `1.0.0`, and is not claimed to be bug-free.
- The five primary compatibility profiles A_ESX_OX, B_QB_QBINV, C_QB_OX, D_QBOX_OX and E_ESX_NATIVE are live-verified.
- `qb-inventory` intentionally declares `metadataFilter=false`; metadata-filtered query/removal fails closed.
- ESX native inventory intentionally does not claim modern metadata-filtering semantics.
- `qs-inventory` has adapter architecture but is not included in the verified compatibility matrix.
- `nexm_notify` is supported/recommended; separate N_NATIVE_NOTIFY live-certification evidence is not asserted by this package.
- `nexm_core` is not intended to be hot-restarted in production; foundational dependency changes should use a full FXServer restart.
- Server→client generic RPC is intentionally not provided.
- Service API versions are integer-based and separate from resource SemVer.
- Discord webhook outage/recovery, long soak and normal-operation performance measurements are separate operational evidence and are not inferred from validator stress/hitch warnings.
