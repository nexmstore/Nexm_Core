# NEXM Core Phase 5 — Networking & Security

Phase 5 implements only the mandatory component-readiness correction plus client→server→client RPC, the server-internal event bus, server-side permissions, rate limiting, payload validation, ownership cleanup, and security hardening. Notify, gameplay products, Phone, Dispatch, Target, Housing, and Phase 6 work remain out of scope.

## Core READY vs component readiness

`NEXM.IsReady()` means Core infrastructure and its configured base framework platform initialized successfully. It does not mean every optional integration exists.

Inventory is now an optional component:

- `Config.Inventory = 'none'` → inventory health `DISABLED`; Core may be `READY`; `NEXM.Inventory.*` returns `INVENTORY_DISABLED` for otherwise valid calls.
- `Config.Inventory = 'auto'` with no supported backend → inventory health `UNAVAILABLE`; Core may be `READY`; diagnostics warn.
- auto with multiple real backends and no explicit priority remains fail-closed with `AMBIGUOUS_INVENTORY_INTEGRATION`; Core does not pretend an inventory was selected, but the optional component does not globally block Core READY.
- a selected inventory remains sticky; another backend is never hot-selected during failure.

The framework remains the configured base platform. Framework loss can move Core to `DEGRADED`; optional integration loss does not redefine global Core readiness.

## Resource requirements

`NEXM.Resources.Register` accepts resource-owned requirements such as:

```lua
requirements = {
    framework = true,
    frameworkCapabilities = { 'money.cash' },
    integrations = {
        inventory = {
            required = true,
            capabilities = { 'metadataFilter' }
        }
    }
}
```

Initial unmet requirements reject registration with structured dependency/capability errors. Already registered resources are revalidated on component changes and transition between `ACTIVE` and `DEGRADED`. Core never calls `StopResource` to enforce product dependencies.

## RPC

Server resource facade:

- `NEXM.Callback.Register(name, handler, options)`

Client resource facade:

- `NEXM.Callback.Await(name, payload, options)`

Callbacks are stored by server-side owner + local callback name. The client-supplied owner is routing information only and is never treated as authorization.

Supported registration options:

- `rateLimit = { limit, window }`
- `permission = 'localPermissionName'`
- `requireCharacter = true|false`
- `validate = function(payload) ... end`

The server-generated callback context contains source, callback owner, canonical character identifier, characterSessionId, and `IsCurrentSession()`. A callback response is rejected with `STALE_CHARACTER_SESSION` if the authoritative session changed while the handler was running. This protects transport responses only; a handler that performs delayed gameplay mutations must still revalidate before that mutation.

RPC direction in Phase 5 is only client → server → client response. No server→client request RPC, client→client RPC, or server→server RPC is implemented.

### Timeout and request IDs

Client default timeout: 10000 ms. Allowed override range: 250–60000 ms. Timed-out pending requests are removed and late responses are ignored.

Request IDs and callback names are bounded and validated. Duplicate active request IDs are rejected without executing the handler twice. Transport duplicate protection is not business idempotency; a malicious client can submit a different request ID.

### Payload bounds

Incoming request payload limits:

- maxDepth: 8
- maxEntries: 128 per table
- maxStringLength: 2048
- maxTotalNodes: 512
- maxKeyLength: 128

Outgoing response limits:

- maxDepth: 8
- maxEntries: 128 per table
- maxStringLength: 4096
- maxTotalNodes: 512
- maxKeyLength: 128

Only finite numbers, strings, booleans, nil, and recursively safe tables are accepted. Functions, threads, userdata, invalid table keys, excessive nesting/size, and cycles are rejected. Invalid outgoing callback responses become `RPC_INVALID_RESPONSE`; raw unsupported values are never intentionally sent to the client.

## Internal event bus

Server API:

- `NEXM.Events.On(name, handler)`
- `NEXM.Events.Emit(name, payload)`

Logical event names require an explicit domain prefix such as `justice:violation` or `core:ready`. Event names are not owner-prefixed because cross-product subscriptions are intentional; listener registrations still record `ownerResource` for cleanup and diagnostics.

The bus is server-local. Its implementation does not use `RegisterNetEvent` or `TriggerClientEvent`. Each listener runs independently under protected execution and receives its own deep validated payload snapshot, so one listener cannot mutate the payload observed by another.

Core emits internal component/dependency signals including `core:ready`, `core:componentStateChanged`, `core:resourceDependencyChanged`, `core:frameworkDegraded`, and `core:frameworkRecovered`.

## Permissions

Server-only API:

- `NEXM.Permissions.Define(name, policy)`
- `NEXM.Permissions.Has(source, name)`
- `NEXM.Permissions.HasAny(source, names)`

Definitions are owner-qualified internally and cleaned on resource stop. The same local permission name may exist under two resources; one resource cannot replace another resource's definition.

V1 policy providers:

- ACE
- normalized job + minimum grade
- normalized duty requirement
- selected framework permission/group where the adapter formally supports it
- protected custom server resolver

Modes `any` and `all` are supported. Ordinary denial returns `false, nil`; unknown permission fails closed with `PERMISSION_NOT_DEFINED`. A custom resolver exception returns `PERMISSION_RESOLVER_ERROR` and is logged. Duty-required job policy grants only when normalized duty is explicitly true; unsupported duty denies.

Framework permission capability now has an implementation contract: if `framework.permissions=true`, the adapter must expose `HasFrameworkPermission`. ESX uses the current xPlayer group, QBCore uses its authoritative server `HasPermission`, and Qbox uses current server ACE semantics rather than relying on its deprecated compatibility permission export.

## Rate limiting

Server API:

- `NEXM.RateLimit.Check(source, key, { limit, window })`
- `NEXM.RateLimit.Reset(source, key)`

Public keys are internally qualified by resource owner. Buckets are hash-map based with lazy window expiry; there is no thread or timer per bucket/source/callback.

The runtime clock uses `GetGameTimer()` with wrap compensation to preserve monotonic elapsed time across the 32-bit timer wrap; the test harness uses a monotonic test/fallback clock.

Session-scoped buckets reset when the normalized character session changes. All source buckets are removed on disconnect, so numeric source reuse does not inherit a previous player's rate-limit punishment. The global RPC source limiter is deliberately source-scoped rather than character-scoped and persists across character switches until disconnect.

RPC has two limiter levels:

1. global per-source limiter before callback lookup/endpoint execution;
2. callback-specific limiter after callback resolution.

Unknown callback name rotation therefore cannot bypass the global source protection.

## Ownership and cleanup

`onResourceStop` cleans resource-owned callbacks, internal event listeners, permission definitions, rate-limit keys, readiness registrations, services, features, integration registrations, lifecycle subscriptions, migrations, and cached public facades. The same resource can cleanly register again after restart.

Client pending RPC promises track the requesting client resource and are resolved/removed when that client resource stops.

## Security conclusions

- No generic client money or inventory mutation endpoint exists.
- Callback owner/resource names supplied over the wire are routing only, never authorization.
- Client identity, job, grade, permission, canonical identifier, and session claims are ignored for authoritative permission/session decisions.
- Callback registry contents are not exposed to clients.
- Duplicate request IDs do not execute the same active request twice, but business mutation idempotency remains the gameplay resource's responsibility.
- Incoming and outgoing payloads are bounded and cycle-safe.
- Stale character sessions cannot receive successful old-session RPC responses.
- Internal domain events are not automatically networked.
- Unknown permissions fail closed.
- Resource/source cleanup prevents registration and rate-bucket leakage during development restarts/source reuse.

## Upstream framework permission references inspected

- ESX Legacy: `esx-framework/esx_core`, commit `fe59ca0bd6da59e2ec6eb4a8d06ece312e96ae7a`; current xPlayer `getGroup()` inspected.
- QBCore: `qbcore-fivem/qb-core`, commit `9b3cddcce93e5e12cbcf6b47b866b687d32ac7bf`; current server `QBCore.Functions.HasPermission` inspected.
- Qbox: `Qbox-project/qbx_core`, commit `c1c3ca16721cd14eb814cfb95e8f8631690d247d`; current permission compatibility export is deprecated, so the adapter uses server-authoritative ACE semantics.

## Real FXServer validation

**NOT EXECUTED** in this environment. Before NEXM Core 1.0 production release, execute at minimum:

- RPC from an actual client resource;
- successful callback and permission denial paths;
- RPC timeout and late response;
- duplicate raw RPC request;
- callback resource restart and client resource restart;
- character switch while a callback is yielded;
- ACE permission;
- normalized job/grade/duty permission;
- callback spam and unknown-name rotation spam;
- framework stop/recovery during permission/RPC usage;
- Core restart with online players/resources;
- `Config.Inventory='none'` and auto/no-inventory Core READY behavior.

## Performance

Phase 5 adds no permanent per-player networking loop, permission polling, callback polling, or per-rate-bucket timer. RPC work occurs only on requests, events only on emit, permissions only on checks, and rate limits use O(1)-style hash lookups with lazy expiry/cleanup. Idle overhead remains negligible.
