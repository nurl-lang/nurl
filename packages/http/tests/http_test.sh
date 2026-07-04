#!/usr/bin/env bash
# ============================================================
#  tests/http_test.sh — build the HttpApp smoke server and drive
#  the full facade over curl: routing, path params, POST body,
#  static fallback, 404, panic→500 recovery, CORS preflight, and
#  keep-alive survival after a handler panic.
#
#  Run from the package dir:  ./tests/http_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t http-test.XXXXXX)"
SERVE_PID=""
cleanup() { [ -n "$SERVE_PID" ] && kill "$SERVE_PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/2] build tests/smoke.nu"
if ! $NURL tests/smoke.nu "$WORK/smoke" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build smoke server:"; tail -8 "$WORK/build.err"; exit 1
fi

echo "[2/2] drive the facade over HTTP"
mkdir -p "$WORK/webroot"
printf 'STATIC-OK' > "$WORK/webroot/file.txt"
PORT=$((20000 + RANDOM % 20000))
"$WORK/smoke" --port "$PORT" --webroot "$WORK/webroot" 2>"$WORK/serve.err" &
SERVE_PID=$!
for _ in $(seq 1 50); do
    curl -s -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null && break
    sleep 0.1
done

B="http://127.0.0.1:$PORT"
[ "$(curl -s "$B/")" = "hello from http" ] && ok "GET / route" || bad "GET /"
[ "$(curl -s "$B/hi/tero")" = "hi tero" ] && ok "path param :name" || bad "path param"
[ "$(curl -s -X POST "$B/echo" -d '{"a":1}')" = '{"a":1}' ] && ok "POST body echo" || bad "POST echo"
[ "$(curl -s "$B/file.txt")" = "STATIC-OK" ] && ok "static fallback" || bad "static fallback"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$B/nope")
[ "$CODE" = "404" ] && ok "unmatched → 404" || bad "404 ($CODE)"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$B/boom")
[ "$CODE" = "500" ] && ok "handler panic → 500" || bad "panic→500 ($CODE)"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS "$B/")
[ "$CODE" = "204" ] && ok "CORS preflight → 204" || bad "CORS preflight ($CODE)"
curl -s -D- -o /dev/null "$B/" | grep -qi 'access-control-allow-origin: \*' \
    && ok "CORS header on response" || bad "CORS header"
# keep-alive must survive the earlier panic
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$B/")
[ "$CODE" = "200" ] && ok "server alive after panic" || bad "server died after panic ($CODE)"

kill "$SERVE_PID" 2>/dev/null; wait "$SERVE_PID" 2>/dev/null; SERVE_PID=""

echo "== http tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
