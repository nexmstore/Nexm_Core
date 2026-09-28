# Temporary Appearance Recovery

## Purpose

Temporary Appearance Recovery protects players from being stranded in a NEXM-controlled temporary outfit after a resource restart, reconnect, abnormal disconnect, death flow, or full FXServer restart. It is reusable infrastructure and is not specific to PestControl.

It is **not** a wardrobe, skin database, clothing shop, character creator, or framework clothing compatibility layer.

## Persistence

Server-side records are stored in `data/temporary_appearances.json` and cached in memory. Core writes only when a record is saved or cleared. A staged file and backup snapshot are used so an unreadable primary file can fall back safely without crashing Core.

Records are keyed by:

1. Core canonical player identifier (`NEXM.Player.GetIdentifier(source)` strategy); and
2. the resource owner automatically bound by the Core facade.

A consumer cannot choose another player's identifier and cannot clear another resource's record through the public facade. Disconnect does not clear pending recovery.

## Snapshot format

Version 1 stores:

- ped model hash;
- component IDs `0..11`: drawable, texture, palette;
- prop IDs `0..7`: drawable, texture;
- `-1` means no prop.

Payloads are normalized and size-bounded before persistence. Entity handles and client-only references are never stored.

## Server flow

Before applying a temporary outfit:

```lua
local ok, resultOrErr = NEXM.TemporaryAppearance.Save(source, snapshot)
if not ok then
    -- Do not apply the temporary outfit.
    return
end
```

An existing owner record is preserved by default. This prevents a retry while already in a work uniform from overwriting the original civilian snapshot.

To recover:

```lua
local record, err = NEXM.TemporaryAppearance.Get(source)
if not record then return end
-- send/use record.appearance on the client
```

Only after the client has restored and verified the snapshot:

```lua
local ok, err = NEXM.TemporaryAppearance.AcknowledgeRestore(source)
```

If restore fails, do not acknowledge; the record remains available for another attempt.

## Client helpers

```lua
local snapshot, err = NEXM.TemporaryAppearance.Capture()
local ok, err = NEXM.TemporaryAppearance.Restore(snapshot)
local verified, err = NEXM.TemporaryAppearance.Verify(snapshot)
```

If the saved model differs from the current model, `Config.TemporaryAppearance.restoreModel` controls whether Core attempts to load and apply the saved model. When model restore is disabled, mismatch fails safely and the server recovery record should be retained.

## Debug

With `Config.Debug = true`, `/nexmtempappearance` reports only safe summary data: pending owner names and timestamps for the invoking player, or aggregate counts from server console. It does not print canonical identifiers to the player console.

## Core restart rule

`nexm_core` itself is not designed for production hot restart. Deploy this Core update with a full FXServer restart. Dependent resources may restart independently; pending appearance records remain in Core persistence until acknowledged.
