# Security

The client is untrusted. NEXM callback routing/resource ownership is not authorization. Sensitive APIs for money, inventory, permissions, audit and rate-limit state are server-only.

Server derives authoritative identity, job, duty and character session. Network payloads and responses are bounded and reject unsupported/cyclic structures. RPC has global and callback-specific rate limiting, duplicate active request protection and timeout cleanup. Internal events are server-local.

Do not use localized strings as canonical identifiers. Do not treat notifications, Discord webhooks or audit availability as gameplay transaction dependencies.


See `../NETWORK_SURFACE.md` and `../API_FREEZE.md` for the exact release network/API inventory. Never expose server credentials, webhook URLs, license identifiers, raw player objects or database connection strings through diagnostics/RPC errors.
