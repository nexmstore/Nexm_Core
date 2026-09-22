# Logging

`NEXM.Log.Debug/Info/Warn/Error(message, metadata)` automatically attributes the resource-bound owner. `NEXM.Log.IsEnabled(level)` lets products avoid expensive debug metadata work when disabled.

Metadata is bounded and safely serialized. Cycles, functions and unsupported values cannot crash the caller. Repeated warning/error suppression is keyed by owner, level, component, error code and message so unrelated resources/components do not suppress one another.
