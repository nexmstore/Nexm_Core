# Integrations and Components

Gameplay-facing integration access is read-only: `GetName`, `IsAvailable`, `GetCapabilities`, `GetState`, `IsHealthy`. Gameplay code cannot register adapters through the public facade.

`NEXM.Components.Get(name)` and `GetAll()` return immutable status snapshots for `database`, `framework`, `money`, `inventory`, `notify`, `rpc`, and `audit`, including provider, state, capabilities and safe details. Adapter implementation functions are never exposed.
