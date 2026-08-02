#!/usr/bin/env bash
set -Eeo pipefail

for DB in /db.d/*; do
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-'    EOSQL'
        CREATE USER docker;
        CREATE DATABASE docker;
        GRANT ALL PRIVILEGES ON DATABASE docker TO docker;
    EOSQL
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-'    EOSQL'
        -- 1. Create User if not exists, and ensure password is set/updated
        CREATE USER docker IF NOT EXISTS WITH PASSWORD '$NEW_USER_PASSWORD';
        -- 2. Create Database if not exists
        CREATE DATABASE docker IF NOT EXISTS;
        -- 3. Restrict Access: Revoke connect access to default system databases
        REVOKE CONNECT ON DATABASE postgres FROM docker;
        REVOKE CONNECT ON DATABASE template0 FROM docker;
        REVOKE CONNECT ON DATABASE template1 FROM docker;
        -- 4. Grant Access: Allow connect only to the 'docker' database
        GRANT CONNECT ON DATABASE docker TO docker;
    EOSQL
    # 5. Grant Schema Permissions inside the 'docker' database
    # We must connect to the 'docker' DB specifically to grant table/schema access
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "docker" <<-'    EOSQL'
        -- Grant usage on the public schema
        GRANT USAGE ON SCHEMA public TO docker;
        -- Grant all privileges on existing tables
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO docker;
        -- Grant all privileges on existing sequences (for auto-increment IDs)
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO docker;
        -- Ensure future tables/sequences are also accessible
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO docker;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO docker;
    EOSQL
done
