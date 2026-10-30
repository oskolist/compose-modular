#!/usr/bin/env bash
# Idempotent provisioning of per-consumer databases on the shared postgres
# service. Mounted by compose into /docker-entrypoint-initdb.d/00-databases.sh,
# so the custom entrypoint re-runs it on EVERY start (not only the first init).
#
# A consumer gets its own database + role by dropping an env-style declaration
# file into the shared /db.d volume (bind-mounted from
# "data/postgres/db.d/"). Each file defines:
#
#   DB_NAME      database name        (required)
#   DB_USER      role/login name      (optional, defaults to DB_NAME)
#   DB_PASSWORD  password for the role (optional; if empty, no password is set)
#   DB_OWNER     database owner       (optional, defaults to DB_USER)
#
# Example (data/postgres/db.d/forgejo.env):
#   DB_NAME=forgejo
#   DB_USER=forgejo
#   DB_PASSWORD=s3cr3t
#
# Consumers then connect with:
#   postgres://<DB_USER>:<DB_PASSWORD>@postgres:5432/<DB_NAME>
set -Eeo pipefail
shopt -s nullglob

# Run SQL against the admin database as the postgres superuser over the unix
# socket (the temp server only listens on the socket).
psql_admin() {
    PGHOST= PGHOSTADDR= PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}" \
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" "$@"
}

processed=0
for f in /db.d/*; do
    [ -f "$f" ] || continue
    processed=1
    echo "[databases.sh] Processing declaration: $(basename "$f")"

    DB_NAME=''; DB_USER=''; DB_PASSWORD=''; DB_OWNER=''
    # shellcheck disable=SC1090
    . "$f"

    DB_USER="${DB_USER:-$DB_NAME}"
    DB_OWNER="${DB_OWNER:-$DB_USER}"

    if [ -z "$DB_NAME" ]; then
        echo "[databases.sh] WARNING: '$(basename "$f")' has no DB_NAME; skipping" >&2
        continue
    fi

    # 1) Role: create if missing.
    psql_admin --set "db_user=$DB_USER" <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = :'db_user') THEN
        EXECUTE format('CREATE ROLE %I LOGIN', :'db_user');
    END IF;
END
$$;
SQL
    # (Re)set the password whenever one is provided (idempotent).
    if [ -n "$DB_PASSWORD" ]; then
        psql_admin --set "db_user=$DB_USER" --set "db_pw=$DB_PASSWORD" <<'SQL'
ALTER ROLE :"db_user" WITH LOGIN PASSWORD :'db_pw';
SQL
    fi

    # 2) Database: create if missing, owned by DB_OWNER.
    psql_admin --set "db_name=$DB_NAME" --set "db_owner=$DB_OWNER" <<'SQL'
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'db_owner')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name')\gexec
SQL

    # 3) Privileges inside the new database.
    psql_admin --set "db_name=$DB_NAME" --set "db_user=$DB_USER" --set "db_owner=$DB_OWNER" <<'SQL'
GRANT ALL PRIVILEGES ON DATABASE :"db_name" TO :"db_user";
ALTER DATABASE :"db_name" OWNER TO :"db_owner";
GRANT USAGE ON SCHEMA public TO :"db_user";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO :"db_user";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO :"db_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO :"db_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO :"db_user";
SQL

    echo "[databases.sh] Database '$DB_NAME' (user '$DB_USER', owner '$DB_OWNER') is ready."
done

[ "$processed" = 0 ] && echo "[databases.sh] No database declarations found in /db.d."
