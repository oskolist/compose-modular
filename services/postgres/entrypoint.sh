#!/usr/bin/env bash
# Custom entrypoint for the shared "postgres" service.
#
# It reuses the official docker-library/postgres entrypoint by `source`-ing it,
# so the cluster bootstrap (initdb, pg_hba.conf, temp-server juggling) stays in
# sync with upstream. On top of that, every script mounted under
# /docker-entrypoint-initdb.d/ is (re)run on EVERY start — not only on the first
# init — so per-consumer databases declared via files in the shared /db.d volume
# (see databases.sh) are (re)provisioned idempotently whenever postgres is
# (re)started, even after a new consumer has been added to /db.d without
# re-initialising the data directory.
#
# Scripts are invoked through docker_process_init_files, so they may be *.sh
# (executed if executable, sourced otherwise), *.sql, *.sql.gz, etc.
#
# References:
#   - https://github.com/docker-library/postgres/blob/master/docker-entrypoint.sh
#   - https://github.com/docker-library/postgres/pull/496  (sourcing the entrypoint)
#   - https://github.com/docker-library/postgres/issues/151 (multiple databases)
set -Eeo pipefail

# Reuse the official entrypoint's helper functions instead of copy/pasting them.
_entry="$(command -v docker-entrypoint.sh || true)"
[ -n "$_entry" ] || _entry='/usr/local/bin/docker-entrypoint.sh'
# shellcheck disable=SC1090
source "$_entry"

# Default to running the server (mirrors the official "postgres" handling).
if [ "$#" -eq 0 ] || [ "$1" != 'postgres' ]; then
    set -- postgres "$@"
fi

docker_setup_env
docker_create_db_directories

# The official image runs as root; fix ownership of PGDATA and drop privileges by
# re-executing ourselves as the postgres user. Re-execing THIS script (via
# "$BASH_SOURCE") keeps our custom "always-init" logic below.
if [ "$(id -u)" = '0' ]; then
    exec gosu postgres "$BASH_SOURCE" "$@"
fi

# ----- below this point we run as the (unprivileged) postgres user -----

# Make PostgreSQL listen on every interface so other containers can reach it via
# the "postgres" service name. The official image defaults to 'localhost'.
ensure_listen_addresses() {
    local conf="$PGDATA/postgresql.conf"
    [ -f "$conf" ] || return 0
    grep -qE '^[[:space:]]*listen_addresses[[:space:]]*=' "$conf" || \
        printf "listen_addresses = '*'\n" >> "$conf"
}

# True iff /docker-entrypoint-initdb.d/ exists and is non-empty.
initdb_scripts_present() {
    [ -d /docker-entrypoint-initdb.d ] || return 1
    local _f
    for _f in /docker-entrypoint-initdb.d/*; do
        [ -e "$_f" ] && return 0
    done
    return 1
}

if [ -z "$DATABASE_ALREADY_EXISTS" ]; then
    # Brand-new data directory: bootstrap the cluster.
    docker_verify_minimum_env
    docker_error_old_databases

    # check dir permissions to reduce likelihood of half-initialized database
    ls /docker-entrypoint-initdb.d/ > /dev/null

    docker_init_database_dir
    ensure_listen_addresses
    pg_setup_hba_conf "$@"

    # PGPASSWORD is required for psql when authentication is required for 'local'
    # connections via pg_hba.conf and is otherwise harmless.
    export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"

    docker_temp_server_start "$@"
    docker_setup_db
    # provision per-consumer databases (databases.sh) right away, on first init
    initdb_scripts_present && docker_process_init_files /docker-entrypoint-initdb.d/*
    docker_temp_server_stop
    unset PGPASSWORD

    printf '\nPostgreSQL init process complete; ready for start up.\n\n'
else
    # Existing data directory: (re)provision consumer databases idempotently so
    # newly-dropped declaration files in /db.d take effect on restart without
    # wiping the data directory. Init scripts must be idempotent.
    ensure_listen_addresses
    if initdb_scripts_present; then
        export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"
        docker_temp_server_start "$@"
        docker_process_init_files /docker-entrypoint-initdb.d/*
        docker_temp_server_stop
        unset PGPASSWORD
    fi
fi

# Don't leak SUPERUSER credentials into the running postgres server's process env.
unset "${!POSTGRES_@}"

exec "$@"
