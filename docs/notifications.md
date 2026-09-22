# Notifications

Server:

```lua
NEXM.Notify.Send(source, message, type, duration, options)
```

Client:

```lua
NEXM.Notify.Send(message, type, duration, options)
```

Types: `info`, `success`, `warning`, `error`. Duration is bounded (default 5000 ms; configured safe range 500–60000 ms).

Supported providers: `nexm_notify` (recommended), `ox_lib`, ESX, QBCore, Qbox, and `custom` where implemented. Products must call only the Core API above; they must not call `lib.notify()` or `exports['nexm_notify']:Notify()` directly.

When `nexm_notify` is selected, client calls are rendered through its client export and server calls use the native `nexm_notify:notify` server→client event. NEXM Notify v1.0.3 supports `title`, `message`, `duration`, `type`, and `id`; per-notification `position` is not supported because position is configured globally in the renderer. Renderer limits are normalized at the provider boundary (title 80, message 300, duration 1000–30000 ms) without changing the Core public contract.

`nexm_notify` is optional and never gates Core READY. It may be stopped/started/restarted independently; Core resolves its current resource state/export at dispatch time and does not cache the renderer export.

Auto mode uses a sticky primary. If fallback is enabled, a deterministic temporary fallback may be used; when the primary recovers it is resumed. With fallback disabled, provider loss yields `NOTIFY_UNAVAILABLE`.
