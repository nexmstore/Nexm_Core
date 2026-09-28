# NEXM Core 1.0.0-rc.1.hotfix.4

Build: `mvp_rc1_tempappearance_7f2c4a91`

Purpose: add reusable, persistent Temporary Appearance Recovery infrastructure without adding a framework clothing dependency.

New public namespaces:

- Server: `NEXM.TemporaryAppearance.Save/Get/Has/Clear/AcknowledgeRestore`
- Client: `NEXM.TemporaryAppearance.Capture/Restore/Verify`

Persistence: `data/temporary_appearances.json` with staged + backup writes. Records survive disconnect/full FXServer restart and are owner-isolated.

Deploy with a full FXServer restart because Core/import build identity changes.
