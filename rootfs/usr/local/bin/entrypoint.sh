#!/bin/bash
# Container init for the all-in-one Brightbean Studio image.
# Runs as root, prepares /config, then hands off to supervisord, which runs
# postgres (embedded mode only), gunicorn and the publishing worker as $PUID.
set -euo pipefail

log() { echo "[entrypoint] $*"; }

CONFIG_DIR=/config
SECRETS_FILE="$CONFIG_DIR/secrets.env"
PGDATA="$CONFIG_DIR/postgres"
APP_USER=brightbean

# ---------------------------------------------------------------------------
# User / permissions (Unraid default: nobody:users = 99:100)
# ---------------------------------------------------------------------------
PUID=${PUID:-99}
PGID=${PGID:-100}

if [ "$PUID" = "0" ]; then
    APP_USER=root
else
    getent group "$APP_USER" >/dev/null || groupadd -o -g "$PGID" "$APP_USER"
    groupmod -o -g "$PGID" "$APP_USER"
    id -u "$APP_USER" >/dev/null 2>&1 \
        || useradd -o -u "$PUID" -g "$PGID" -d "$CONFIG_DIR" -s /usr/sbin/nologin -M "$APP_USER"
    usermod -o -u "$PUID" -g "$PGID" "$APP_USER" >/dev/null
fi
export APP_USER

mkdir -p "$CONFIG_DIR" /app/media /run/postgresql
chown "$PUID:$PGID" "$CONFIG_DIR" /app/media /run/postgresql
# Only fix ownership when it is off, so large media libraries don't slow boot.
if [ "$(stat -c %u /app/media)" != "$PUID" ] || [ -n "$(find /app/media -maxdepth 2 ! -user "$PUID" -print -quit)" ]; then
    log "fixing ownership of /app/media"
    chown -R "$PUID:$PGID" /app/media
fi

as_app() { if [ "$APP_USER" = root ]; then "$@"; else gosu "$APP_USER" "$@"; fi; }

# ---------------------------------------------------------------------------
# Secrets: generated once, persisted in /config. ENCRYPTION_KEY_SALT must never
# change after the first start or stored platform tokens become unreadable.
# ---------------------------------------------------------------------------
touch "$SECRETS_FILE"
chmod 600 "$SECRETS_FILE"
chown "$PUID:$PGID" "$SECRETS_FILE"

gen_secret() { python -c 'import secrets; print(secrets.token_urlsafe(50))'; }

persist_secret() {
    local name=$1
    if [ -n "${!name:-}" ]; then
        return
    fi
    if ! grep -q "^${name}=" "$SECRETS_FILE"; then
        log "generating $name (stored in $SECRETS_FILE)"
        echo "${name}=$(gen_secret)" >>"$SECRETS_FILE"
    fi
    export "$name=$(grep "^${name}=" "$SECRETS_FILE" | tail -n1 | cut -d= -f2-)"
}

persist_secret SECRET_KEY
persist_secret ENCRYPTION_KEY_SALT

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
export APP_URL=${APP_URL:-http://localhost:${PORT:-8000}}
if [ -z "${ALLOWED_HOSTS:-}" ]; then
    app_host=$(python -c 'import os, urllib.parse; print(urllib.parse.urlparse(os.environ["APP_URL"]).hostname or "")')
    ALLOWED_HOSTS="${app_host:+$app_host,}localhost,127.0.0.1"
fi
# The healthcheck talks to 127.0.0.1, so keep it allowed.
case ",$ALLOWED_HOSTS," in
    *",*,"* | *",127.0.0.1,"*) ;;
    *) ALLOWED_HOSTS="$ALLOWED_HOSTS,127.0.0.1" ;;
esac
export ALLOWED_HOSTS
export DEBUG=${DEBUG:-false}
export STORAGE_BACKEND=${STORAGE_BACKEND:-local}
export MEDIA_ROOT=${MEDIA_ROOT:-/app/media}
export SERVE_MEDIA=${SERVE_MEDIA:-true}
export SIGNUP_MODE=${SIGNUP_MODE:-open}
if [ -z "${EMAIL_BACKEND_TYPE:-}" ]; then
    if [ -n "${EMAIL_HOST:-}" ]; then EMAIL_BACKEND_TYPE=smtp; else EMAIL_BACKEND_TYPE=console; fi
fi
export EMAIL_BACKEND_TYPE
export GUNICORN_WORKERS=${GUNICORN_WORKERS:-2}
export GUNICORN_THREADS=${GUNICORN_THREADS:-4}
export PORT=${PORT:-8000}

# ---------------------------------------------------------------------------
# Database: embedded PostgreSQL unless DATABASE_URL points elsewhere
# ---------------------------------------------------------------------------
if [ -z "${DATABASE_URL:-}" ]; then
    export EMBEDDED_DB=true
    persist_secret POSTGRES_PASSWORD
    export PGDATA

    if [ ! -s "$PGDATA/PG_VERSION" ]; then
        log "initialising embedded PostgreSQL $PG_MAJOR in $PGDATA"
        mkdir -p "$PGDATA"
        chown "$PUID:$PGID" "$PGDATA"
        chmod 700 "$PGDATA"
        pwfile=$(mktemp)
        echo "$POSTGRES_PASSWORD" >"$pwfile"
        chown "$PUID:$PGID" "$pwfile"
        as_app initdb -D "$PGDATA" -U postgres --auth-local=trust --auth-host=scram-sha-256 \
            --pwfile="$pwfile" --encoding=UTF8 --locale=C.UTF-8 >/dev/null
        rm -f "$pwfile"
        cat >>"$PGDATA/postgresql.conf" <<EOF

# brightbean-studio container
listen_addresses = '127.0.0.1'
unix_socket_directories = '/run/postgresql'
EOF
        new_db=1
    else
        existing=$(cat "$PGDATA/PG_VERSION")
        if [ "$existing" != "$PG_MAJOR" ]; then
            log "ERROR: $PGDATA was created by PostgreSQL $existing, this image ships $PG_MAJOR."
            exit 1
        fi
        chown -R "$PUID:$PGID" "$PGDATA"
        new_db=0
    fi

    as_app pg_ctl -D "$PGDATA" -w -t 60 start -o "-c listen_addresses=127.0.0.1" >/dev/null
    if [ "$new_db" = 1 ]; then
        as_app psql -h /run/postgresql -U postgres -v ON_ERROR_STOP=1 -q -c "CREATE DATABASE brightbean"
    fi
    export DATABASE_URL="postgres://postgres:${POSTGRES_PASSWORD}@127.0.0.1:5432/brightbean"
else
    export EMBEDDED_DB=false
    log "using external database from DATABASE_URL"
fi

# ---------------------------------------------------------------------------
# Migrations
# ---------------------------------------------------------------------------
cd /app
log "running migrations"
migrate_status=0
as_app python manage.py migrate --noinput || migrate_status=$?

if [ "$EMBEDDED_DB" = true ]; then
    as_app pg_ctl -D "$PGDATA" -w -m fast stop >/dev/null
fi
[ "$migrate_status" = 0 ] || { log "ERROR: migrations failed"; exit "$migrate_status"; }

# Snapshot the environment so `docker exec ... bb-run <cmd>` sees the same
# settings (generated secrets, embedded DATABASE_URL) as the services.
install -d -m 700 /run/brightbean
export -p | grep -vE '^declare -x (HOME|HOSTNAME|PWD|SHLVL|OLDPWD|TERM|_)=' >/run/brightbean/env
chmod 600 /run/brightbean/env

if [ "$#" -gt 0 ]; then
    exec gosu "$APP_USER" "$@"
fi

log "starting services (embedded db: $EMBEDDED_DB)"
exec /usr/bin/supervisord -n -c /etc/supervisor/brightbean.conf
