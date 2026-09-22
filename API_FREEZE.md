# NEXM Core 1.0 Public API Freeze Inventory

This file inventories the public API frozen for the 1.0 release line. Breaking changes after final 1.0 require a major version unless a backwards-compatible path exists.

## Server facade

Root: `IsReady`, `GetStatus`.

- `Version`: `Get`, `Compare`, `Satisfies`, `Require`
- `Validate`: shared validation helpers
- `Log`: `Debug`, `Info`, `Warn`, `Error`, `IsEnabled`
- `DB`: `Query`, `Single`, `Scalar`, `Insert`, `Update`, `Transaction`
- `Migrations`: `Register`, `Run`
- `Resources`: `Register`, `IsRunning`, `Get`, `GetAll`
- `Services`: `Register`, `Get`, `Has`, `GetMetadata`
- `Features`: `Register`, `Has`, `Get`, `GetMetadata`
- `Integrations`: `GetName`, `IsAvailable`, `GetCapabilities`, `GetState`, `IsHealthy`
- `Components`: `Get`, `GetAll`
- `Player`: `Get`, `Exists`, `GetIdentifier`, `GetCharacterIdentifier`, `GetAccountIdentifier`, `GetLicense`, `GetCharacterName`, `GetJob`, `GetJobGrade`, `GetSource`, `IsOnline`, `GetFrameworkObject`
- `Jobs`: `Get`, `Has`, `HasAny`, `MinimumGrade`, `IsOnDuty`
- `Money`: `Get`, `Add`, `Remove`, `CanAfford`
- `Inventory`: `HasItem`, `GetItemCount`, `AddItem`, `RemoveItem`, `CanCarry`, `GetItems`
- `Notify`: `Send`
- `Locale`: `Register`, `Get`, `SetFallback`
- `Audit`: `Log`
- `Callback`: `Register`
- `RateLimit`: `Check`, `Reset`
- `Permissions`: `Define`, `Has`, `HasAny`
- `Events`: `OnReady`, `On`, `Emit`, `OnPlayerLoaded`, `OnPlayerUnloaded`, `OnJobChanged`, `OnDutyChanged`

`Migrations` is retained because it is an approved Phase 2 public contract even though some later condensed namespace lists omitted it. Removing it before 1.0 would break the approved migration-registration model.

## Client facade

- `Player`: `GetLocal`, `IsLoaded`
- `Callback`: `Await`
- `Notify`: `Send`
- `Locale`: `Register`, `Get`, `SetFallback`
- `Events`: `OnPlayerLoaded`, `OnPlayerUnloaded`, `OnJobChanged`, `OnDutyChanged`
- `Validate`
- `Version`: `Get`

## Explicitly absent on client

`Money`, `Inventory`, `Permissions`, `Audit`, `DB`, `Migrations`, `Resources`, `Services`, `Features`, integration registration/mutation, component mutation and rate-limit administration are not client APIs.

## Deprecation policy

The 1.x line keeps backwards compatibility where practical. Deprecated APIs should remain available with documentation/warnings until a major-version boundary. Intentional breaking API changes target 2.0 rather than silently changing 1.x contracts.
