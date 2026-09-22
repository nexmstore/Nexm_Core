# Network / Export Surface Inventory

This inventory is a release security checklist. Routing names are implementation details and are not authorization.

## Exports

| Export | Runtime | Purpose | Intended caller | Security boundary |
|---|---|---|---|---|
| `GetCoreObject` | server | resource-bound server facade | server resources | owner attribution, not authorization |
| `GetCoreObject` | client | safe client facade | client resources | safe subset only |

## NEXM network events

| Event | Direction | Purpose | Authority rule |
|---|---|---|---|
| `nexm_core:rpc:request` | client → server | callback request transport | client untrusted; server validates/rate-limits/authorizes |
| `nexm_core:rpc:response` | server → client | callback response | matched to active request id |
| `nexm_core:server:requestLocalState` | client → server | request normalized local player snapshot | server derives state; client supplies no identity authority |
| `nexm_core:client:playerState` | server → client | normalized player state | presentation/convenience only |
| `nexm_core:client:playerUnloaded` | server → client | clear normalized local state | server lifecycle authority |
| `nexm_core:client:frameworkUnavailable` | server → client | invalidate convenience state | server lifecycle authority |
| `nexm_core:client:notify` | server → client | normalized notification display | no corresponding generic client→server send-to-player endpoint |

Internal EventBus events are server-local and are not registered as network events. There are no generic client-accessible money or inventory mutation events.
