# Intro
[PostgreSQL](https://www.postgresql.org/) running in a dedicated, shared container. One instance is meant to be consumed by several other services (e.g. **Forgejo**, **Strfry**, **Pocket-ID**, …) — each consumer gets its **own database** (and role) instead of everyone shipping its own embedded database.

# Status
not tested

# Notes
- The data directory is persisted at `../../data/postgres/` (`PGDATA` = `/var/lib/postgresql/data`) on the host; the superpassword/`POSTGRES_PASSWORD` is only read from `services/postgres/.env` (git-ignored) and is never committed.
- PostgreSQL is set to `listen_addresses = '*'` (done by `entrypoint.sh`) so other containers can reach it over the shared Compose network as the **`postgres`** service name (`postgres:5432`). No port is published to the host.
- The custom `entrypoint.sh` (modeled on [docker-library/postgres#496](https://github.com/docker-library/postgres/pull/496)) reuses the official entrypoint's functions **and** re-runs `/docker-entrypoint-initdb.d/*` on every start, so consumer databases are re-provisioned idempotently whenever postgres is restarted.
- Consumer databases are declared as one env-style file per consumer dropped into the shared `data/postgres/db.d/` volume (mounted read-only into the container at `/db.d`). Drop a new file there and restart postgres to add a consumer — no data wipe, no migration of existing databases needed.

## Give a consumer its own database
Create `data/postgres/db.d/<consumer>.env`:
```env
DB_NAME=forgejo          # the database name (required)
DB_USER=forgejo          # role/login (optional, defaults to DB_NAME)
DB_PASSWORD=s3cr3t       # role password (optional; omit to leave unset)
# DB_OWNER=forgejo        # owner role (optional, defaults to DB_USER)
```
Then point the consumer at it, e.g. for **Forgejo**:
```env
FORGEJO_DB_TYPE=postgresql
FORGEJO_DATABASE=forgejo
FORGEJO_DB_USER=forgejo
FORGEJO_DB_PASSWORD=s3cr3t
FORGEJO_DB_HOST=postgres
FORGEJO_DB_PORT=5432
```
The connection string consumers can use is:
`postgres://<DB_USER>:<DB_PASSWORD>@postgres:5432/<DB_NAME>`
