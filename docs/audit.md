# Audit

Server-only:

```lua
NEXM.Audit.Log({
  action = 'condition_changed',
  actor = source,
  subject = characterIdentifier,
  severity = 'info',
  data = { field = 'value' }
})
```

Core automatically records the resource owner. Player actor identity is resolved from authoritative Core player state; system actions can omit actor. Audit data is bounded serializable data.

Supported backend architecture: console/local log, database, Discord webhook and custom. Database uses `nexm_audit_log` when enabled. Discord identifiers are omitted by default. Backend jobs use one bounded queue/worker with bounded retries/backoff. `Audit.Log` success means a valid entry was accepted; a later external backend failure does not roll back gameplay.

Automatic retention is disabled by default (`RetentionDays = 0`); operators must establish retention before production or explicitly configure a future policy.
