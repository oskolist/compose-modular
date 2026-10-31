# Intro
[syncstorage-rs](https://github.com/mozilla-services/syncstorage-rs) is Mozilla's Firefox Sync Storage server, written in Rust. This service runs the **self-hosted** flavor where the *syncstorage* API and the *tokenserver* API run together in a single container, backed by the shared PostgreSQL instance. Firefox clients are pointed at `https://<SYNCSTORAGERS_DOMAIN>/1.0/sync/1.5`.

The official pre-built image is used (no from-source build): `ghcr.io/mozilla-services/syncstorage-rs/syncserver-postgres:0.24.0`, pinned by digest in `images.env`.

# Status
untested

# Requirements
- The shared `postgres` service must be enabled (see `services/postgres/`). `syncstorage-rs` declares `depends_on: postgres` with `condition: service_healthy`, so it will not start until PostgreSQL is ready **and its schema has been provisioned**.
- The image published on `ghcr.io` targets `linux/amd64` — run this on an amd64 host.

## Wire up the shared database
This is the only service in the stack that currently consumes the shared PostgreSQL instance. It pioneers the `db.d` consumer pattern, so a one-off provisioning step is required:

1. Enable the `postgres` service in `compose.yaml.template` (uncomment `services/postgres/compose.yaml`).
2. Create the consumer declaration — **the file lives under the git-ignored `data/` tree, so it is never committed**:
   ```bash
   mkdir -p data/postgres/db.d
   cat > data/postgres/db.d/syncstorage.env <<'EOF'
   DB_NAME=syncserver      # the database (matches SYNC_*__DATABASE_URL below)
   DB_USER=sync            # role/login the syncserver connects as
   DB_PASSWORD=<same as SYNCSTORAGERS_DB_PASSWORD>
   EOF
   ```
   Restart `postgres` once so `databases.sh` provisions the `sync` role and `syncserver` database.

3. Copy the env template and fill the secrets:
   ```bash
   cp services/syncstorage-rs/.env.template services/syncstorage-rs/.env
   ```
   - `SYNCSTORAGERS_MASTER_SECRET` — Hawk master secret, used to derive the signing + token secrets. Generate with:
     ```bash
     cat /dev/urandom | base32 | head -c64
     ```
   - `SYNCSTORAGERS_METRICS_HASH_SECRET` — a *second*, independent secret used to hash FxA metrics UIDs. **Do not reuse the master secret.**
   - `SYNCSTORAGERS_DB_PASSWORD` — password for the `sync` PostgreSQL role. It is embedded into a `postgresql://` URL, so use URL-safe characters only (base32/hex recommended); it **must match** `DB_PASSWORD` in the `db.d/syncstorage.env` file above.

The resulting connection string consumed by the server is:
`postgresql://sync:<DB_PASSWORD>@postgres:5432/syncserver`

## Configuration notes
- Both the syncstorage schema and the tokenserver schema are migrated automatically on first boot (`tokenserver.run_migrations=true` is set in `compose.yaml`).
- `tokenserver.init_node_url` is set to `https://${SYNCSTORAGERS_DOMAIN}` and bootstraps the `sync-1.5` service + storage node record so clients immediately resolve the storage endpoint.
- Defaults target **production** Firefox Accounts (`api.accounts.firefox.com` / `oauth.accounts.firefox.com`). Set `SYNCSTORAGERS_FXA_EMAIL_DOMAIN` / `SYNCSTORAGERS_FXA_OAUTH_SERVER_URL` to the stage endpoints if you are testing against staging.
- `SYNCSTORAGERS_PORT` defaults to `8011` to avoid clashing with the upstream default of `8000`. TLS termination is handled by nginx; `syncstorage-rs` listens on `127.0.0.1` (host bind) / `0.0.0.0` (in-container).

## Point Firefox at it
In `about:config`, set the tokenserver URI to your domain (the `/1.0/sync/1.5` suffix is the standard entry point served by the tokenserver, which reverse-proxies through nginx as `location /`):
```
identity.sync.tokenserver.uri = https://sync.$MAIN_DOMAIN/1.0/sync/1.5
```
Then sign in to Sync with your Firefox Account. The first sign-in triggers node registration against the tokenserver.

## Healthcheck
`GET /__heartbeat__` — curls `http://localhost:${SYNCSTORAGERS_PORT:-8011}/__heartbeat__` from inside the container (`-f` fails the check if the DB is unreachable). Use `docker compose ps` to see the `healthy` status.

# TODO
- Add a dedicated `ipmonitor.compose.yaml`? Not needed: syncstorage-rs exposes no public-IP-dependent feature (nginx does the public binding).
- Verify with a real Firefox client end-to-end once booted.
