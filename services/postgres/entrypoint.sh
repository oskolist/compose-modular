#!/usr/bin/env bash
set -Eeo pipefail

source "$(which docker-entrypoint.sh)"

if [ "$#" -eq 0 ] || [ "$1" != 'postgres' ]; then
    set -- postgres "$@"
fi

docker_setup_env
docker_create_db_directories

if [ "$(id -u)" = '0' ]; then
    # then restart script as postgres user
    exec gosu postgres "$BASH_SOURCE" "$@"
fi

if [ -z "$DATABASE_ALREADY_EXISTS" ]; then
    docker_verify_minimum_env
    docker_error_old_databases

    # check dir permissions to reduce likelihood of half-initialized database
    ls /docker-entrypoint-initdb.d/ > /dev/null

    docker_init_database_dir
    pg_setup_hba_conf "$@"

    # PGPASSWORD is required for psql when authentication is required for 'local' connections via pg_hba.conf and is otherwise harmless
    # e.g. when '--auth=md5' or '--auth-local=md5' is used in POSTGRES_INITDB_ARGS
    export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"
    docker_temp_server_start "$@"

    docker_setup_db
    docker_process_init_files /docker-entrypoint-initdb.d/*

    docker_temp_server_stop
    unset PGPASSWORD
else
    docker_temp_server_start "$@"
    docker_process_init_files /always-initdb.d/*
    docker_temp_server_stop
fi

exec "$@"
