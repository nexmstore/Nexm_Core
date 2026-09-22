# Configuration

Important selectors in `config.lua`:

- `Config.Framework`: `auto`, supported framework name, or standalone policy.
- `Config.Inventory`: `auto`, `none`, or a supported inventory adapter.
- `Config.Notify`: `auto`, `none`, `nexm_notify`, `ox_lib`, `esx`, `qbcore`, `qbox`, `custom`. The shipped production default is `nexm_notify`.
- `Config.NotifyFallback`: allows deterministic temporary fallback when the sticky primary notify provider is unavailable.
- `Config.NotifyPriority`: ordered list such as `{ 'nexm_notify', 'ox_lib', 'framework' }`. In `auto` mode the native NEXM renderer is preferred when available.
- `Config.Locale`: requested locale; `Config.LocaleFallback` defaults to `en`.
- `Config.Logging.level`: minimum local log level.
- `Config.Audit`: audit enablement, backends, queue limits and optional webhook.

`Config.Audit.RetentionDays = 0` means automatic retention deletion is disabled. This is the safe default.


Startup validation rejects invalid framework/inventory/notify selectors, invalid locale identifiers, unsupported log levels, unsafe money/RPC limits, malformed network bounds, and invalid audit queue/backend settings with structured startup failure rather than delayed nil errors.
