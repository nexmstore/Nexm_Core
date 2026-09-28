# NEXM Core 1.0.0-rc.1.hotfix.4 — Temporary Appearance Recovery

- Public version: `1.0.0-rc.1.hotfix.4`
- Internal build: `mvp_rc1_tempappearance_7f2c4a91`
- Release status: `MVP_RC_TEMP_APPEARANCE_RECOVERY`
- Date: 2026-09-27

This build extends the validated hotfix.3 Core with a generic, restart-safe Temporary Appearance Recovery service for NEXM-controlled temporary outfits. It stores native ped appearance snapshots by canonical player identity and calling-resource owner, survives full FXServer restart through JSON persistence, preserves the original snapshot on duplicate saves, and requires explicit acknowledgement before cleanup.

No framework clothing integration and no SQL migration are added. Existing framework, inventory, notify, money, identity, permissions, RPC and database contracts remain unchanged.

The Core half is implemented in this artifact. Product-specific integration (for example NEXM PestControl shift start/end/reconnect flows) is intentionally not bundled into this Core-only ZIP and must be validated in the consuming product separately.
