# NEXM Core Phase 6 Notes

## Scope completed

Phase 6 adds platform support services and developer experience only: normalized optional notifications, resource-owned localization, non-transactional audit infrastructure, crash-safe structured logging, service API-version polish, read-only integration/component diagnostics, and developer documentation. No gameplay resource or Phase 7 work is included.

## Notification model

Notify is optional and never gates Core READY. `Config.Notify='none'` yields DISABLED; auto with no provider yields UNAVAILABLE. Auto chooses a sticky primary from deterministic priority. When fallback is enabled a temporary fallback may be used, but the primary resumes when healthy. Server gameplay uses one normalized server→client event. There is no generic client→server notify endpoint.

Inspected upstream references:
- ox_lib 3.39.0, commit `b8f5a04351b1d427e0e112150d36094e9889ec7b`
- ESX Legacy/es_extended 1.15.2, commit `fe59ca0bd6da59e2ec6eb4a8d06ece312e96ae7a`
- QBCore 1.3.0, commit `9b3cddcce93e5e12cbcf6b47b866b687d32ac7bf`
- Qbox 1.24.0, commit `c1c3ca16721cd14eb814cfb95e8f8631690d247d`

## Locale model

Locale strings are owned by the product resource. Fallback is requested locale → resource fallback → configured global fallback → `en` → key. Tables are flattened into safe dot keys and copied on registration. Interpolation is literal `{name}` substitution only; no code/template execution exists. Server and client have separate runtime registries; register common strings from a product shared script instead of globally broadcasting all translations.

## Audit model

`NEXM.Audit.Log` is server-only and resource-bound. Player actor identity is resolved from authoritative Player state. Audit payloads are bounded/cycle-safe. Backends are console, database, Discord and custom. Database/webhook/custom processing is supporting observability: backend failures are retried/dropped by bounded policy and never roll back a gameplay mutation. Discord omits character identifiers by default. Automatic retention is disabled by default (`RetentionDays=0`).

The optional database table is created by the audit component when the database backend is enabled; it is deliberately not a mandatory Core migration so audit availability cannot become a Core READY dependency.

## Logger/services/diagnostics

Logger metadata is bounded and fails safe. Repeated warning/error suppression includes owner and component. Services support exact integer `apiVersion` requirements and retain deep read-only API facades. `NEXM.Components` returns immutable snapshots. `nexm:status verbose` displays component capabilities, resource requirements, service API versions, integrations, RPC/rate state and audit queue/backend metrics without player identifiers or secrets.

## Automated result

After final Phase 6 changes the complete Phase 2–6 regression must be executed. See `TEST_RESULTS.md` for the final recorded count.

## Real FXServer status

**NOT EXECUTED in this build environment.** Before NEXM Core 1.0 production release, validate at minimum:

1. ox_lib, ESX, QBCore and Qbox notifications in real clients.
2. normalized server→client notify event and local client notify API.
3. notify fallback enabled/disabled and provider restart/recovery.
4. server/client locale registration from a shared product script and locale fallback.
5. Discord audit success/failure/retry behavior against a controlled webhook.
6. database audit inserts and database-outage recovery.
7. audit queue pressure with webhook unavailable.
8. product resource stop/restart locale/service cleanup.
9. Core restart with existing resources/players.
10. Phase 5 live security matrix (RPC, stale session, permission, rate limiting) after Phase 6 is installed.
