# Player

Server `NEXM.Player` exposes normalized active-character snapshots and identifiers. Canonical character identity is opaque and namespaced by framework. Snapshots are deep copies; consumers cannot mutate Core cache.

Important methods include `Get`, `Exists`, `GetIdentifier`, `GetCharacterIdentifier`, `GetAccountIdentifier`, `GetLicense`, `GetCharacterName`, `GetJob`, `GetJobGrade`, `GetSource`, `IsOnline`, and `GetFrameworkObject`.

Use strict numeric server sources. Numeric strings are not coerced. `characterSessionId` protects source reuse and character switching across async-sensitive flows.
