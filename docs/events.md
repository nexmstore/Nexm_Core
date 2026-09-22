# Internal Events

Server-only internal bus:

```lua
NEXM.Events.On('example:changed', function(payload) end)
NEXM.Events.Emit('example:changed', payload)
```

Logical event names use explicit domain prefixes. Listener ownership is separate from event namespace to allow cross-product subscriptions. Each listener gets an isolated deep payload snapshot and one listener throwing does not stop others. Internal events are not automatically network events.
