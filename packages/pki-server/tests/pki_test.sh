#!/usr/bin/env bash
# pki_test.sh — End-to-end integration test suite for pure-NURL PKI Server.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
PKG_ROOT="$(cd "$HERE/.." && pwd)"

PORT=$(( 18000 + ( $$ % 1000 ) ))
TMPDIR="$(mktemp -d /tmp/pki-test-XXXXXX)"
BIN="$TMPDIR/pki-server"
INIT_KEY="test-device-init-key-99"
MGMT_KEY="test-management-api-key-42"

cleanup() {
    if [ -n "${SERVER_PID:-}" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

echo "==> Building pki-server binary..."
mkdir -p "$PKG_ROOT/deps"
[ -e "$PKG_ROOT/deps/http" ] || ln -s "../../http" "$PKG_ROOT/deps/http"
(
    cd "$PKG_ROOT"
    NURL_STDLIB="$REPO_ROOT" "$REPO_ROOT/nurl.sh" src/main.nu "$BIN"
)

echo "==> Starting pki-server on port $PORT..."
"$BIN" \
    --port "$PORT" \
    --host "127.0.0.1" \
    --ca-cert "$TMPDIR/ca.crt" \
    --ca-key "$TMPDIR/ca.key" \
    --crl-file "$TMPDIR/ca.crl" \
    --index-file "$TMPDIR/index.txt" \
    --serial-file "$TMPDIR/serial" \
    --initial-dir "$TMPDIR/initial" \
    --certs-dir "$TMPDIR/certificates" \
    --init-key "$INIT_KEY" \
    --mgmt-key "$MGMT_KEY" \
    --ca-cn "Test PKI Root CA" &
SERVER_PID=$!

# Wait for server to become healthy
READY=0
for i in $(seq 1 50); do
    if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 0.1
done

if [ "$READY" -ne 1 ]; then
    echo "ERROR: Server failed to start on port $PORT"
    exit 1
fi
echo "==> Server started (PID: $SERVER_PID)"

# ── Test 1: GET /health ───────────────────────────────────────────────
echo "--> Test 1: GET /health"
HEALTH_RESP=$(curl -sf "http://127.0.0.1:$PORT/health")
echo "$HEALTH_RESP" | grep -q '"status":"healthy"' || { echo "FAIL: health status missing"; exit 1; }

# ── Test 2: GET /ca-cert ──────────────────────────────────────────────
echo "--> Test 2: GET /ca-cert"
CA_RESP=$(curl -sf "http://127.0.0.1:$PORT/ca-cert")
echo "$CA_RESP" | grep -q "BEGIN CERTIFICATE" || { echo "FAIL: ca-cert missing PEM"; exit 1; }

# ── Test 3: POST /init ────────────────────────────────────────────────
echo "--> Test 3: POST /init"
# 3a. Invalid init key -> 401
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/init" \
    -H "Content-Type: application/json" \
    -d '{"device_id":"dev-100","key":"wrong-key"}')
[ "$HTTP_CODE" -eq 401 ] || { echo "FAIL: expected 401 for wrong key, got $HTTP_CODE"; exit 1; }

# 3b. Valid init key -> 200 + certificate
INIT_RESP=$(curl -sf -X POST "http://127.0.0.1:$PORT/init" \
    -H "Content-Type: application/json" \
    -d "{\"device_id\":\"dev-100\",\"key\":\"$INIT_KEY\"}")
echo "$INIT_RESP" | grep -q "BEGIN CERTIFICATE" || { echo "FAIL: init response missing cert"; exit 1; }

# Extract certificate JSON string
# Using python or awk/sed to parse JSON certificate field
DEV100_CERT=$(echo "$INIT_RESP" | sed -n 's/.*"certificate":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g')
[ -n "$DEV100_CERT" ] || { echo "FAIL: could not parse initial cert"; exit 1; }

# 3c. Duplicate init -> 403
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/init" \
    -H "Content-Type: application/json" \
    -d "{\"device_id\":\"dev-100\",\"key\":\"$INIT_KEY\"}")
[ "$HTTP_CODE" -eq 403 ] || { echo "FAIL: expected 403 for duplicate init, got $HTTP_CODE"; exit 1; }

# ── Test 4: POST /renew_initial_cert ──────────────────────────────────
echo "--> Test 4: POST /renew_initial_cert"
# 4a. Mismatched cert -> 401
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/renew_initial_cert" \
    -H "Content-Type: application/json" \
    -d "{\"device_id\":\"dev-100\",\"key\":\"$INIT_KEY\",\"initial_cert\":\"bogus-cert\"}")
[ "$HTTP_CODE" -eq 401 ] || { echo "FAIL: expected 401 for mismatched cert, got $HTTP_CODE"; exit 1; }

# 4b. Valid cert -> 200 + new cert
ESCAPED_CERT=$(echo "$DEV100_CERT" | awk '{printf "%s\\n", $0}')
RENEW_RESP=$(curl -sf -X POST "http://127.0.0.1:$PORT/renew_initial_cert" \
    -H "Content-Type: application/json" \
    -d "{\"device_id\":\"dev-100\",\"key\":\"$INIT_KEY\",\"initial_cert\":\"$ESCAPED_CERT\"}")
echo "$RENEW_RESP" | grep -q "BEGIN CERTIFICATE" || { echo "FAIL: renewal missing cert"; exit 1; }
DEV100_RENEWED_CERT=$(echo "$RENEW_RESP" | sed -n 's/.*"certificate":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g')

# ── Test 5: POST /request-cert (JSON) ─────────────────────────────────
echo "--> Test 5: POST /request-cert (JSON)"
ESCAPED_RENEWED=$(echo "$DEV100_RENEWED_CERT" | awk '{printf "%s\\n", $0}')
REQ_RESP=$(curl -sf -X POST "http://127.0.0.1:$PORT/request-cert" \
    -H "Content-Type: application/json" \
    -d "{\"device_id\":\"dev-100\",\"initial_cert\":\"$ESCAPED_RENEWED\",\"validity_days\":90}")
echo "$REQ_RESP" | grep -q '"certificate":' || { echo "FAIL: request-cert missing certificate"; exit 1; }
echo "$REQ_RESP" | grep -q '"private_key":' || { echo "FAIL: request-cert missing private_key"; exit 1; }
echo "$REQ_RESP" | grep -q '"ca_certificate":' || { echo "FAIL: request-cert missing ca_certificate"; exit 1; }
echo "$REQ_RESP" | grep -q '"expires":' || { echo "FAIL: request-cert missing expires"; exit 1; }

OP_CERT=$(echo "$REQ_RESP" | sed -n 's/.*"certificate":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g')

# ── Test 6: POST /request-cert (Form POST) ────────────────────────────
echo "--> Test 6: POST /request-cert (Form POST)"
# Initialize a second device dev-200
INIT_RESP2=$(curl -sf -X POST "http://127.0.0.1:$PORT/init" \
    -H "Content-Type: application/json" \
    -d "{\"device_id\":\"dev-200\",\"key\":\"$INIT_KEY\"}")
DEV200_CERT=$(echo "$INIT_RESP2" | sed -n 's/.*"certificate":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g')

FORM_RESP=$(curl -sf -X POST "http://127.0.0.1:$PORT/request-cert" \
    --data-urlencode "device_id=dev-200" \
    --data-urlencode "initial_cert=$DEV200_CERT" \
    --data-urlencode "validity_days=180")
echo "$FORM_RESP" | grep -q "Certificate Generated Successfully" || { echo "FAIL: HTML form cert generation failed"; exit 1; }

# ── Test 7: POST /revoke & GET /crl ───────────────────────────────────
echo "--> Test 7: POST /revoke & GET /crl"
# 7a. GET /crl without API key -> 401
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/crl")
[ "$HTTP_CODE" -eq 401 ] || { echo "FAIL: expected 401 on /crl without key, got $HTTP_CODE"; exit 1; }

# 7b. GET /crl with query param -> 200
CRL_RESP=$(curl -sf "http://127.0.0.1:$PORT/crl?api_key=$MGMT_KEY")
echo "$CRL_RESP" | grep -q "BEGIN X509 CRL" || { echo "FAIL: CRL missing header"; exit 1; }

# 7c. POST /revoke without API key -> 401
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/revoke" \
    -H "Content-Type: application/json" \
    -d '{"serial":"123456"}')
[ "$HTTP_CODE" -eq 401 ] || { echo "FAIL: expected 401 on /revoke without key, got $HTTP_CODE"; exit 1; }

# 7d. POST /revoke with X-API-Key by certificate PEM -> 200 + invalidates initial enrollment
ESCAPED_OP_CERT=$(echo "$OP_CERT" | awk '{printf "%s\\n", $0}')
REVOKE_RESP=$(curl -sf -X POST "http://127.0.0.1:$PORT/revoke" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $MGMT_KEY" \
    -d "{\"certificate\":\"$ESCAPED_OP_CERT\"}")
echo "$REVOKE_RESP" | grep -q '"status":"success"' || { echo "FAIL: revoke response not success"; exit 1; }
echo "$REVOKE_RESP" | grep -q "BEGIN X509 CRL" || { echo "FAIL: revoke response missing updated CRL"; exit 1; }

# 7e. Post-revocation check: dev-100 initial certificate must now be invalidated
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/request-cert" \
    -H "Content-Type: application/json" \
    -d "{\"device_id\":\"dev-100\",\"initial_cert\":\"$ESCAPED_RENEWED\"}")
[ "$HTTP_CODE" -eq 401 ] || { echo "FAIL: expected 401 on revoked device request-cert, got $HTTP_CODE"; exit 1; }

# ── Test 8: Web UI pages ──────────────────────────────────────────────
echo "--> Test 8: Web UI Pages"
curl -sf "http://127.0.0.1:$PORT/" | grep -q "Welcome to your Private PKI Service" || { echo "FAIL: index page"; exit 1; }
curl -sf "http://127.0.0.1:$PORT/request-cert" | grep -q "Request a New Certificate" || { echo "FAIL: request-cert page"; exit 1; }
curl -sf "http://127.0.0.1:$PORT/revoke" | grep -q "Revoke a Certificate" || { echo "FAIL: revoke page"; exit 1; }
curl -sf "http://127.0.0.1:$PORT/api" | grep -q "REST API Documentation" || { echo "FAIL: api docs page"; exit 1; }
curl -sf "http://127.0.0.1:$PORT/css/style.css" | grep -q ":root" || { echo "FAIL: css stylesheet"; exit 1; }

# ── Test 9: OpenSSL Interoperability Verification ──────────────────────
echo "--> Test 9: OpenSSL Compatibility Checks"
if command -v openssl >/dev/null 2>&1; then
    # Verify CA certificate parsing
    openssl x509 -in "$TMPDIR/ca.crt" -text -noout >/dev/null 2>&1 || { echo "FAIL: OpenSSL cannot parse CA cert"; exit 1; }

    # Verify CRL parsing
    openssl crl -in "$TMPDIR/ca.crl" -text -noout >/dev/null 2>&1 || { echo "FAIL: OpenSSL cannot parse CRL"; exit 1; }

    # Save dev-200 operational cert from Test 6 and verify against CA
    ESCAPED_DEV200=$(echo "$DEV200_CERT" | awk '{printf "%s\\n", $0}')
    DEV200_REQ_RESP=$(curl -sf -X POST "http://127.0.0.1:$PORT/request-cert" \
        -H "Content-Type: application/json" \
        -d "{\"device_id\":\"dev-200\",\"initial_cert\":\"$ESCAPED_DEV200\",\"validity_days\":365}")
    DEV200_OP_CERT=$(echo "$DEV200_REQ_RESP" | sed -n 's/.*"certificate":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g')
    echo "$DEV200_OP_CERT" > "$TMPDIR/dev200.crt"

    openssl verify -CAfile "$TMPDIR/ca.crt" "$TMPDIR/dev200.crt" >/dev/null 2>&1 || { echo "FAIL: OpenSSL CA verification of issued cert failed"; exit 1; }
    echo "    OpenSSL CA verification: OK (valid signature & chain)"
fi

echo "=================================================="
echo "  ALL E2E INTEGRATION TESTS PASSED SUCCESSFULLY!  "
echo "=================================================="
