# Troubleshooting

Run `nexm:status` from the server console. Use `nexm:status verbose` for component capabilities, resource requirements, service/API versions, integration states, pending RPC/rate counts and audit queue metrics.

Common states:
- Core READY + Inventory DISABLED: intentional `Config.Inventory='none'`.
- Core READY + Inventory UNAVAILABLE: no usable auto inventory; only products requiring inventory degrade/fail registration.
- Notify UNAVAILABLE: Core remains READY; check configured provider, fallback policy and client resources.
- Audit DEGRADED: inspect DB/webhook/custom backend state; gameplay remains independent.
- `CAPABILITY_UNAVAILABLE`: product requirement exceeds selected adapter capability.


Release-hardening errors should be actionable. If Core reports configuration validation failure, correct the named config field before restart. A migration checksum mismatch means an already-applied historical migration changed and must not be silently overwritten.
