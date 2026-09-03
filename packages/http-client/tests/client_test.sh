#!/usr/bin/env bash
# ============================================================
#  tests/client_test.sh — build the HttpClient facade + a test
#  server (on the `http` package) and drive the client against it
#  over both plaintext (HTTP/1.1) and TLS (ALPN → HTTP/2): protocol
#  selection, connection reuse, redirects, the redirect cap, cookies,
#  gzip decoding, POST bodies, and post-quantum key exchange.
#
#  Run from the package dir:  ./tests/client_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t http-client-test.XXXXXX)"
SRV_PLAIN=""; SRV_TLS=""
cleanup() {
    [ -n "$SRV_PLAIN" ] && kill "$SRV_PLAIN" 2>/dev/null
    [ -n "$SRV_TLS" ] && kill "$SRV_TLS" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "[1/4] build tests/server.nu"
if ! $NURL tests/server.nu "$WORK/server" >/dev/null 2>"$WORK/server.err"; then
    echo "FAIL: could not build server:"; tail -12 "$WORK/server.err"; exit 1
fi

echo "[2/4] build tests/client.nu"
if ! $NURL tests/client.nu "$WORK/client" >/dev/null 2>"$WORK/client.err"; then
    echo "FAIL: could not build client:"; tail -12 "$WORK/client.err"; exit 1
fi

echo "[3/4] mint a self-signed cert + start servers"
# Self-signed P-256 leaf for 127.0.0.1 via openssl (test-only).
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 1 -nodes \
    -subj "/CN=127.0.0.1" >/dev/null 2>&1 || { echo "FAIL: openssl cert mint"; exit 1; }

HTTP_PORT=$((21000 + RANDOM % 10000))
HTTPS_PORT=$((HTTP_PORT + 1))
"$WORK/server" --port "$HTTP_PORT" 2>"$WORK/srv-plain.err" &
SRV_PLAIN=$!
"$WORK/server" --port "$HTTPS_PORT" --tls --cert "$WORK/cert.pem" --key "$WORK/key.pem" 2>"$WORK/srv-tls.err" &
SRV_TLS=$!

# Wait for both to answer.
for _ in $(seq 1 50); do
    curl -s -o /dev/null "http://127.0.0.1:$HTTP_PORT/" 2>/dev/null && break
    sleep 0.1
done
for _ in $(seq 1 50); do
    curl -sk -o /dev/null "https://127.0.0.1:$HTTPS_PORT/" 2>/dev/null && break
    sleep 0.1
done

echo "[4/4] drive the facade"
"$WORK/client" --http-port "$HTTP_PORT" --https-port "$HTTPS_PORT"
RC=$?

if [ "$RC" != 0 ]; then
    echo "--- server (plaintext) stderr ---"; tail -8 "$WORK/srv-plain.err"
    echo "--- server (TLS) stderr ---"; tail -8 "$WORK/srv-tls.err"
fi
exit $RC
