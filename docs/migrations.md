# Migrations

Products explicitly register immutable ordered migrations through `NEXM.Migrations`. Core tracks resource, migration ID, checksum and applied time in `nexm_migrations`. Applied definition checksum changes fail closed.

Core migrations run before framework/player services. Audit schema is deliberately not a mandatory Core migration because audit observability must not become a transactional Core READY dependency.
