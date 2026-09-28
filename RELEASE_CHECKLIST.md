# 1.0.0-rc.1.hotfix.4 Release Checklist

## Core package

- [x] Version/build identity updated.
- [x] Temporary appearance JSON data file included.
- [x] Server persistence module loaded before public API.
- [x] Client capture/restore/verify helper loaded before client public API.
- [x] Owner is bound to calling resource; arbitrary client player identifiers are not accepted.
- [x] Duplicate save preserves original snapshot by default.
- [x] Clear/ack affects only the calling resource owner record.
- [x] `playerDropped` does not clear records.
- [x] No SQL migration or framework clothing dependency added.
- [x] CFX open-source escrow policy retained.

## Live gate

- [ ] Consuming product normal save/apply/restore/ack flow.
- [ ] Consumer resource restart recovery.
- [ ] Full FXServer restart + reconnect recovery.
- [ ] Disconnect/reconnect recovery.
- [ ] Forced persistence failure blocks temporary outfit application.
- [ ] Restore verification failure retains record.
- [ ] Model mismatch behavior validated with configured `restoreModel`.
- [ ] Multiple owner isolation validated in live runtime.

These live gates cannot be truthfully marked complete by a Core-only package without the consuming product integration.
