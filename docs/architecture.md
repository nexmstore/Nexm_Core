# Architecture

NEXM Core follows: Public Facade → Domain Services → Managers/Registries → Adapters → Platform Services → FiveM.

Gameplay products never need to call ESX/QBCore/Qbox/inventory APIs directly. Public server facades are resource-bound for ownership and cleanup. Client state is intentionally smaller and never exposes money, inventory, permissions, audit or rate-limit mutation APIs.

Core readiness and component health are distinct. Optional integrations can be disabled or unavailable while Core remains READY. Products declare requirements at registration time.

Notify, audit and external logging are supporting observability services: their failure does not roll back unrelated gameplay state.
