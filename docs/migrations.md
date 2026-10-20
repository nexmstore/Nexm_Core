# Migrations

Products explicitly register immutable ordered migrations through `NEXM.Migrations`. Core tracks resource, migration ID, checksum and applied time in `nexm_migrations`. Applied definition checksum changes fail closed.

Core migrations run before framework/player services. Audit schema is deliberately not a mandatory Core migration because audit observability must not become a transactional Core READY dependency.

## Async / coroutine boundary

Migration execution performs asynchronous database work. `Migrations.Run()` deliberately does **not** keep a broad `pcall`/`xpcall` frame around the yielding DB path. Expected SQL, checksum, bookkeeping and validation failures are propagated with explicit `false, structured_error` returns.

Hotfix.9 removes the Lua callback function-reference path to oxmysql entirely. Core sends DB requests to a Core-owned JavaScript bridge; that bridge awaits oxmysql's `*_async` exports in JavaScript and returns only plain local-event data to Lua. Lua therefore never supplies an oxmysql callback function reference, while the public `NEXM.DB.*` API remains unchanged.

The temporary hotfix.7/8 server-local `Migrations.Run()` request/result proxy was also removed. `NEXM.Migrations.Run()` again uses the same generic transport wrapper as the rest of the Core facade. DB async isolation now happens below the migration service, inside Core.

## Cleanup and duplicate runs

Only one migration run may be active per resource. If a resource stops during an active run, registry cleanup is deferred through `cleanupPending` until the explicit migration result returns. Applied migrations are never rerun when the stored checksum matches.

## Diagnostics

Detailed migration SQL/operation diagnostics are off by default. Enable temporarily with either:

```cfg
set nexm_debug_migrations 1
```

or `Config.Database.migrationDebug = true`. Diagnostics print SQL text and parameter counts, never parameter values.

DB/migration failures return `false, structured_error` and are never treated as success.
