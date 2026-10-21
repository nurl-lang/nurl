#!/usr/bin/env bash
# packages/psql/tests/live_smoke.sh — the codec tests, then the live tests
# under AddressSanitizer against a real server.
#
#   ./tests/live_smoke.sh            (from packages/psql)
#
# With PSQL_TEST_PORT set it uses that server (PSQL_TEST_HOST / _USER /
# _PASSWORD / _DB as live_test.nu reads them). Otherwise it starts a
# throwaway cluster with the PostgreSQL server binaries it finds
# (initdb / pg_ctl on PATH or under /usr/lib/postgresql/*/bin): SCRAM-SHA-256
# logins, TLS on with a self-signed certificate, on 127.0.0.1:$PSQL_SMOKE_PORT
# (default 55432), in a temporary directory removed afterwards. The server
# refuses to run as root; as root the cluster runs as $PSQL_SMOKE_USER
# (default postgres) through setpriv.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"          # packages/psql
REPO="$(cd "$HERE/../.." && pwd)"                  # repo root
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"
OUT="$(mktemp -d)"
cluster=""

cleanup() {
    if [ -n "$cluster" ]; then
        as_pg "$PG_BIN/pg_ctl" -D "$cluster/data" -m immediate stop >/dev/null 2>&1 || true
        rm -rf "$cluster"
    fi
    rm -rf "$OUT"
}
trap cleanup EXIT

as_pg() {
    if [ "$(id -u)" = 0 ]; then setpriv --reuid="${PSQL_SMOKE_USER:-postgres}" --regid="${PSQL_SMOKE_USER:-postgres}" --init-groups "$@"
    else "$@"; fi
}

cd "$HERE"
[ -e deps/cli ] || { mkdir -p deps && ln -sfn ../../cli deps/cli; }

echo "[smoke] codec tests (no server)"
"$NURL_SH" tests/wire_test.nu "$OUT/wire_test" >/dev/null
"$OUT/wire_test"

if [ -z "${PSQL_TEST_PORT:-}" ]; then
    PG_BIN="$(dirname "$(command -v initdb 2>/dev/null || ls -d /usr/lib/postgresql/*/bin/initdb 2>/dev/null | sort -V | tail -1)")"
    if [ ! -x "$PG_BIN/initdb" ]; then
        echo "[smoke] no PSQL_TEST_PORT and no PostgreSQL server binaries — live tests skipped" >&2
        exit 0
    fi
    port="${PSQL_SMOKE_PORT:-55432}"
    cluster="$(mktemp -d /tmp/nurl-psql-smoke.XXXXXX)"
    chmod 755 "$cluster"
    [ "$(id -u)" = 0 ] && chown "${PSQL_SMOKE_USER:-postgres}" "$cluster"
    echo "secret" > "$cluster/pw"
    as_pg "$PG_BIN/initdb" -D "$cluster/data" -U nurl --pwfile="$cluster/pw" --auth=scram-sha-256 -E UTF8 >/dev/null
    as_pg openssl req -new -x509 -days 2 -nodes -subj "/CN=localhost" \
        -keyout "$cluster/data/server.key" -out "$cluster/data/server.crt" >/dev/null 2>&1
    as_pg chmod 600 "$cluster/data/server.key"
    as_pg sh -c "printf '%s\n' \"port = $port\" \"listen_addresses = '127.0.0.1'\" \"unix_socket_directories = '$cluster'\" 'ssl = on' 'fsync = off' >> '$cluster/data/postgresql.conf'"
    as_pg "$PG_BIN/pg_ctl" -D "$cluster/data" -l "$cluster/log" -w start >/dev/null
    export PSQL_TEST_HOST=127.0.0.1 PSQL_TEST_PORT="$port" PSQL_TEST_USER=nurl PSQL_TEST_PASSWORD=secret PSQL_TEST_DB=postgres
    echo "[smoke] throwaway cluster on :$port ($PG_BIN)"
fi

echo "[smoke] live tests (ASan)"
NURL_SAN=1 "$NURL_SH" tests/live_test.nu "$OUT/live_test" >/dev/null
"$OUT/live_test"

echo "[smoke] CLI one-shot"
"$NURL_SH" src/main.nu "$OUT/psql" >/dev/null
PGPASSWORD="${PSQL_TEST_PASSWORD:-}" "$OUT/psql" -h "${PSQL_TEST_HOST:-127.0.0.1}" -p "$PSQL_TEST_PORT" \
    -U "${PSQL_TEST_USER:-postgres}" -d "${PSQL_TEST_DB:-postgres}" --sslmode require -c "select 1 as one"

echo "[smoke] OK"
