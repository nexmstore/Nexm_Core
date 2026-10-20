# NEXM Core Phase 3 - Framework Layer

Phase 3 extends the approved Phase 2 Core Foundation with framework identity/player/job/lifecycle infrastructure only.

## Final capability schema

Canonical schema ownership: `server/framework_contract.lua`.

```lua
capabilities = {
    player = {
        identity = {
            character = true,
            account = true,
            license = true
        },
        job = true,
        duty = true
    },
    jobs = {
        multiple = false
    },
    framework = {
        permissions = false
    }
}
```

Every field is mandatory and boolean. `false` is an explicit unsupported declaration, not a missing value. Additional optional capability groups are accepted only if their leaves are booleans.

## Identity contract

- `NEXM.Player.GetIdentifier(source)` -> canonical opaque active-character key.
- `NEXM.Player.GetCharacterIdentifier(source)` -> framework-native active character identifier.
- `NEXM.Player.GetAccountIdentifier(source)` -> account/user identity where meaningful.
- `NEXM.Player.GetLicense(source)` -> FiveM/Rockstar license identity.

Canonical character keys are constructed as `<framework>:character:<native>` and are treated as opaque strings. Native identifiers may themselves contain colons.

## Duty contract

`NEXM.Jobs.IsOnDuty(source)` returns a real boolean only when `player.duty` is supported. Unsupported duty returns `nil, UNSUPPORTED_FEATURE`; it is not interpreted as off duty. Accordingly, normalized `Player.job.onDuty` is `nil` when unsupported.

## Lifecycle/restart contract

Adapter handlers are physically removed with `RemoveEventHandler` when possible and are also guarded by an adapter generation token. Stale generations cannot modify normalized Core state even if physical handler removal fails.

Selected frameworks are sticky. Framework stop invalidates normalized player cache and fails framework-dependent calls closed. Core never hot-switches to another detected framework mid-session. Recovery accepts only the same selected framework, revalidates/reinitializes it, reattaches lifecycle, and reconstructs loaded characters with new Core `characterSessionId` values.

Cache reconstruction is intentionally marked internally as `reconstructed` and does not emit a normal logical `playerLoaded` event, preventing dependent gameplay resources from accidentally performing duplicate character initialization after a Core restart.

## Security boundary

Server adapters are authoritative for character identity, name, job, grade, and duty. Client local normalized state is convenience-only and is fed from Core normalized updates. Client-supplied citizen IDs, identifiers, jobs, grades, or duty state are never authoritative.
