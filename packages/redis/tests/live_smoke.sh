#!/usr/bin/env bash
# packages/redis/tests/live_smoke.sh — build the redis client and exercise it
# against a live server. Uses $REDIS_PORT (default 16379); if nothing is
# listening there and Docker is available, spins up a throwaway redis:7.
#
#   ./tests/live_smoke.sh
#
# Run from the package root (packages/redis). Expects the monorepo layout so
# NURL_STDLIB and deps/tls resolve.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"          # packages/redis
REPO="$(cd "$HERE/../.." && pwd)"                  # repo root
PORT="${REDIS_PORT:-16379}"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

started_container=0
cleanup() { [ "$started_container" = 1 ] && docker rm -f nurl-redis-smoke >/dev/null 2>&1 || true; }
trap cleanup EXIT

# ── ensure a server ──
if ! (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
    if command -v docker >/dev/null 2>&1; then
        echo "[smoke] no server on :$PORT — starting redis:7 in Docker"
        docker rm -f nurl-redis-smoke >/dev/null 2>&1 || true
        docker run -d --name nurl-redis-smoke -p "$PORT:6379" redis:7 >/dev/null
        started_container=1
        sleep 2
    else
        echo "[smoke] no server on :$PORT and no Docker — start Redis and retry" >&2
        exit 2
    fi
fi

cd "$HERE"

# ── unit-test the RESP codec (no server) ──
echo "[smoke] RESP codec unit tests"
"$NURL_SH" tests/resp_test.nu /tmp/redis_resp_test >/dev/null
/tmp/redis_resp_test

# ── live typed-API test under ASan ──
echo "[smoke] live typed-API test (ASan)"
REDIS_PORT="$PORT" NURL_SAN=1 "$NURL_SH" tests/live_test.nu /tmp/redis_live_test >/dev/null
# live_test.nu hard-codes 16379; align the server port for it
if [ "$PORT" != 16379 ]; then
    echo "[smoke] NOTE: live_test.nu targets 16379; set REDIS_PORT=16379 for it" >&2
fi
/tmp/redis_live_test

# ── one-shot CLI sanity ──
echo "[smoke] CLI one-shot"
"$NURL_SH" src/main.nu /tmp/redis_cli >/dev/null
/tmp/redis_cli -p "$PORT" -c "PING"
/tmp/redis_cli -p "$PORT" -c "SET smoke:key hello"
/tmp/redis_cli -p "$PORT" -c "GET smoke:key"

echo "[smoke] OK"
