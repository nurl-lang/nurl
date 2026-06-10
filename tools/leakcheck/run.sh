#!/usr/bin/env bash
# ============================================================
#  tools/leakcheck/run.sh — HTTP server per-request leak gate
#
#  Builds http_server_leakcheck.nu with ASan+LSan (NURL_SAN=1),
#  serves N requests (hit + 404 + header probe), shuts down via
#  SIGINT, and FAILS if LeakSanitizer reports anything at all.
#
#  Locks the per-request leak class fixed 2026-06-10:
#    * None-placeholder allocations (`@ ?T { F ( string_new ) }`)
#      leaking on every header_get miss — now payload-less `{ F }`
#      backed by gen_agg_lit's zeroinitializer seeding.
#    * __serve_keepalive_loop's pre-allocated panic-500 response
#      leaking on every successful request.
#    * router/route handler closure envs (no closure auto-drop).
#
#  Usage:  ./tools/leakcheck/run.sh   (from the repo root)
#  Exit:   0 = zero leaks · 1 = leaks or harness failure
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/../.."

PORT=8077
BIN=/tmp/nurl_leakcheck_server
LOG=/tmp/nurl_leakcheck.log

NURL_SAN=1 ./nurl.sh -O0 tools/leakcheck/http_server_leakcheck.nu "$BIN" >/dev/null

ASAN_OPTIONS=detect_leaks=1 "$BIN" >"$LOG" 2>&1 &
SRV=$!
trap 'kill -9 $SRV 2>/dev/null || true' EXIT
sleep 1

for _ in $(seq 1 20); do
    curl -s -H "X-Probe: x" "http://127.0.0.1:$PORT/" -o /dev/null
done
curl -s "http://127.0.0.1:$PORT/nosuch" -o /dev/null

kill -INT "$SRV"
# Nudge the accept loops so the workers observe the shutdown flag.
for _ in 1 2 3 4; do curl -s -m 1 "http://127.0.0.1:$PORT/" -o /dev/null 2>/dev/null || true; done

for _ in $(seq 1 15); do
    kill -0 "$SRV" 2>/dev/null || break
    sleep 1
done
if kill -0 "$SRV" 2>/dev/null; then
    echo "FAIL: server did not exit after SIGINT" >&2
    exit 1
fi
trap - EXIT

if [ -s "$LOG" ]; then
    echo "FAIL: LeakSanitizer reported:" >&2
    cat "$LOG" >&2
    exit 1
fi
echo "leakcheck PASS — zero leaks across 21 requests"
