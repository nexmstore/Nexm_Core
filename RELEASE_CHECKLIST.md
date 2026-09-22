# 1.0.0-rc.1.hotfix.3 Release Checklist

## Completed

- [x] Feature freeze maintained; no speculative gameplay/features added.
- [x] Public API, export/network and client-security inventories retained.
- [x] Production manifest excludes tests/mocks and ships the consumer import shim.
- [x] Core/validator offline automated regression baseline clean.
- [x] A_ESX_OX verified in real runtime.
- [x] B_QB_QBINV verified in real runtime.
- [x] C_QB_OX verified in real runtime.
- [x] D_QBOX_OX verified in real runtime.
- [x] E_ESX_NATIVE verified in real runtime.
- [x] Real full FXServer restart baseline evidence retained for A_ESX_OX.
- [x] Core production hot-restart remains outside the supported contract.
- [x] Compatibility documentation synchronized with verified profile state.

## Separate qualification items

- [ ] Record separate N_NATIVE_NOTIFY live-certification evidence if it should be marketed as live-verified rather than supported/recommended.
- [ ] Capture normal-operation resmon/CPU/memory data separately from the heavy validator if desired.
- [ ] Perform desired soak and clean-install/upgrade exercises before final `1.0.0` authorization.
