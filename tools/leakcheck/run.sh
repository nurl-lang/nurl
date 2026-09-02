#!/usr/bin/env bash
# ============================================================
#  tools/leakcheck/run.sh — HTTP server per-request leak gate
#
#  Builds http_server_leakcheck.nu with ASan+LSan (NURL_SAN=1),
#  serves N requests (hit + 404 + header probe) over HTTP/1.1 and over
#  HTTP/2 (prior knowledge on the same port), shuts down via SIGINT,
#  and FAILS if LeakSanitizer reports anything at all.
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

# HTTP/2 over the same port (prior knowledge, RFC 9113 §3.4): 20 one-
# request connections, then one connection carrying 10 requests on
# successive streams, then a 404 — the h2 request/response path must be
# as leak-free per request and per connection as the HTTP/1.1 one.
for _ in $(seq 1 20); do
    curl -s --http2-prior-knowledge -H "X-Probe: x" "http://127.0.0.1:$PORT/" -o /dev/null
done
curl -s --http2-prior-knowledge $(for _ in $(seq 1 10); do printf ' -o /dev/null http://127.0.0.1:%s/' "$PORT"; done)
curl -s --http2-prior-knowledge "http://127.0.0.1:$PORT/nosuch" -o /dev/null

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
echo "leakcheck PASS — zero leaks across 21 HTTP/1.1 + 31 HTTP/2 requests"
