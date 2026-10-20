# NEXM Core Phase 2

This package implements only the approved Core Foundation scope.

## Startup order

1. constants
2. config
3. logger
4. config validation
5. oxmysql verification
6. database connectivity
7. `nexm_migrations` bootstrap table
8. Core migrations
9. platform/registry foundation
10. diagnostics
11. READY

Framework, inventory and notify components intentionally remain `NOT INITIALIZED` until later phases.

## Critical integration rule

The integration manager provides sticky selection and fail-closed ambiguity handling. No inventory/notify adapters are included in Phase 2.

## Ownership rule

Resource-facing registrations receive owner identity from the resource-bound facade. A caller-supplied owner is not trusted when actual invocation context is available. Cross-owner registration replacement is rejected.

## Infrastructure errors

Database and migration infrastructure failures are logged by Core even if the caller ignores returned errors. Logger warning/error deduplication suppresses repeated identical failures within a configurable window.
