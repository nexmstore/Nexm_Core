# Services

Register server-to-server APIs:

```lua
NEXM.Services.Register('justice', api, {
  version = '1.2.0',
  apiVersion = 2,
  capabilities = { search = true }
})
```

Consumers use `Get(name, { apiVersion = 2 })` or `Has`. Resource version and service API version are distinct. API version matching is exact integer matching in V1. Returned service APIs are deep isolated snapshots: consumer mutation cannot alter the authoritative registered service. Across real FiveM resource boundaries the snapshot is intentionally plain/serializable because Lua metatables are not preserved by function-reference serialization; callable service methods remain Cfx function references. Metadata capabilities are copied snapshots. Owner stop removes the service and the same owner can register again after restart.
