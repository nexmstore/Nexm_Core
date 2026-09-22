# Inventory

Server-only API: `HasItem`, `GetItemCount`, `AddItem`, `RemoveItem`, `CanCarry`, optional normalized `GetItems`.

Inventory is independent of framework selection. Capability metadata includes `metadata`, `metadataFilter`, `canCarry`, and `getItems`. Metadata is never silently discarded. If an adapter cannot accurately filter metadata, metadata-sensitive query/removal returns `UNSUPPORTED_FEATURE` rather than falling back to name-only behavior.

`Config.Inventory = 'none'` intentionally disables inventory without preventing Core READY.
