# Localization

Products own their strings:

```lua
NEXM.Locale.Register('en', { welcome = 'Welcome, {name}' })
local text = NEXM.Locale.Get('welcome', { name = 'John' })
```

Fallback order: requested locale → resource-specific fallback → configured global fallback → `en` → key itself. Missing values do not execute code; `{name}` interpolation accepts only strings, finite numbers and booleans. Missing variables remain as placeholders; unsupported types become a safe marker.

Locale registries exist per runtime. To use the same product strings on server and client, register them from a shared product script. Core does not broadcast every product locale table to every client. Localized text is presentation only and must never become a canonical permission/item/callback/business ID.
