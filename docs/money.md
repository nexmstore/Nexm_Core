# Money

Server-only API: `NEXM.Money.Get`, `Add`, `Remove`, `CanAfford`. Canonical accounts are `cash` and `bank`.

Mutation amounts must be finite positive integers within configured limits. Add/Remove require a bounded reason string. Insufficient `CanAfford` is `false,nil`; insufficient `Remove` returns `INSUFFICIENT_FUNDS`.

Money remains framework-backed and character-session aware. No generic client mutation endpoint exists.
