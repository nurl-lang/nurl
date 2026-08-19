#!/usr/bin/env bash
# pki_test.sh — End-to-end integration test suite for pure-NURL PKI Server.
#
# Runs the whole lifecycle twice: once against a classical ECDSA P-256
# CA and once against a post-quantum ML-DSA-65 CA. Every code path in
# the service branches on the CA algorithm, so a single-algorithm run
# only ever covers half of it.
#
# The OpenSSL interop block runs only in the classical pass: OpenSSL
# gained ML-DSA in 3.5, and the ASN.1-level checks that do apply to a PQ
# certificate (asn1parse, x509 -text) are asserted separately.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
PKG_ROOT="$(cd "$HERE/.." && pwd)"

TMPDIR="$(mktemp -d /tmp/pki-test-XXXXXX)"
BIN="$TMPDIR/pki-server"
INIT_KEY="test-device-init-key-99"
MGMT_KEY="test-management-api-key-42"

SERVER_PID=""
cleanup() {
    if [ -n "${SERVER_PID:-}" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

fail() { echo "FAIL: $*"; exit 1; }

# JSON field extraction. The previous suite used a greedy sed, which
# silently matched "ca_certificate" when asked for "certificate" — so
# the OpenSSL chain check was verifying the CA against itself.
jget() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1],""))' "$1"; }

echo "==> Building pki-server binary..."
mkdir -p "$PKG_ROOT/deps"
[ -e "$PKG_ROOT/deps/http" ] || ln -s "../../http" "$PKG_ROOT/deps/http"
(
    cd "$PKG_ROOT"
    NURL_STDLIB="$REPO_ROOT" "$REPO_ROOT/nurl.sh" src/main.nu "$BIN"
)

# ── Startup behaviour with no keys configured ─────────────────────────
echo "--> Test 0: unconfigured keys are generated, not defaulted"
BOOTDIR="$TMPDIR/boot"
mkdir -p "$BOOTDIR"
BOOTPORT=$(( 17000 + ( $$ % 500 ) ))
env -u DEVICE_INIT_KEY -u MANAGEMENT_KEY "$BIN" \
    --port "$BOOTPORT" --host 127.0.0.1 \
    --ca-cert "$BOOTDIR/ca.crt" --ca-key "$BOOTDIR/ca.key" \
    --crl-file "$BOOTDIR/ca.crl" --index-file "$BOOTDIR/index.txt" \
    --initial-dir "$BOOTDIR/initial" --certs-dir "$BOOTDIR/certificates" \
    >"$BOOTDIR/out.log" 2>"$BOOTDIR/err.log" &
BOOT_PID=$!
for _ in $(seq 1 80); do
    curl -sf "http://127.0.0.1:$BOOTPORT/health" >/dev/null 2>&1 && break
    sleep 0.1
done
grep -q "no device initialization key configured" "$BOOTDIR/err.log" \
    || fail "server did not report a generated device key"
grep -q "no management API key configured" "$BOOTDIR/err.log" \
    || fail "server did not report a generated management key"
# The retired placeholders must no longer authenticate anything.
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$BOOTPORT/init" \
    -H "Content-Type: application/json" \
    -d '{"device_id":"dev-x","key":"your-device-init-key"}')
[ "$CODE" -eq 401 ] || fail "shipped placeholder init key still authenticates (got $CODE)"
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://127.0.0.1:$BOOTPORT/crl?api_key=your-management-key-here")
[ "$CODE" -eq 401 ] || fail "shipped placeholder management key still authenticates (got $CODE)"
kill "$BOOT_PID" 2>/dev/null || true
wait "$BOOT_PID" 2>/dev/null || true

# ── Per-algorithm lifecycle ───────────────────────────────────────────
run_suite() {
    ALG="$1"
    PORT="$2"
    WORK="$TMPDIR/$ALG"
    mkdir -p "$WORK"

    echo ""
    echo "=================================================="
    echo "  Algorithm: $ALG"
    echo "=================================================="

    "$BIN" \
        --port "$PORT" \
        --host "127.0.0.1" \
        --algorithm "$ALG" \
        --ca-cert "$WORK/ca.crt" \
        --ca-key "$WORK/ca.key" \
        --crl-file "$WORK/ca.crl" \
        --index-file "$WORK/index.txt" \
        --initial-dir "$WORK/initial" \
        --certs-dir "$WORK/certificates" \
        --init-key "$INIT_KEY" \
        --mgmt-key "$MGMT_KEY" \
        --ca-cn "Test PKI Root CA" >"$WORK/server.log" 2>&1 &
    SERVER_PID=$!

    READY=0
    for _ in $(seq 1 200); do
        if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then READY=1; break; fi
        sleep 0.1
    done
    [ "$READY" -eq 1 ] || { cat "$WORK/server.log"; fail "server failed to start on port $PORT"; }
    echo "==> Server started (PID: $SERVER_PID)"

    # ── Test 1: GET /health ───────────────────────────────────────────
    echo "--> Test 1: GET /health"
    curl -sf "http://127.0.0.1:$PORT/health" >"$WORK/health.json"
    [ "$(jget status <"$WORK/health.json")" = "healthy" ] || fail "health status missing"
    [ "$(jget algorithm <"$WORK/health.json")" = "$ALG" ] || fail "health reports the wrong algorithm"
    if [ "$ALG" = "p256" ]; then
        [ "$(jget post_quantum <"$WORK/health.json")" = "False" ] || fail "p256 claimed post-quantum"
    else
        [ "$(jget post_quantum <"$WORK/health.json")" = "True" ] || fail "$ALG not reported post-quantum"
    fi

    # The CA private key must not be readable by other accounts.
    PERMS=$(stat -c '%a' "$WORK/ca.crt" >/dev/null 2>&1 && stat -c '%a' "$WORK/ca.key")
    [ "$PERMS" = "600" ] || fail "CA private key mode is $PERMS, expected 600"

    # ── Test 2: GET /ca-cert ──────────────────────────────────────────
    echo "--> Test 2: GET /ca-cert"
    curl -sf "http://127.0.0.1:$PORT/ca-cert" >"$WORK/ca.json"
    jget ca_certificate <"$WORK/ca.json" | grep -q "BEGIN CERTIFICATE" || fail "ca-cert missing PEM"

    # ── Test 3: POST /init ────────────────────────────────────────────
    echo "--> Test 3: POST /init"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/init" \
        -H "Content-Type: application/json" \
        -d '{"device_id":"dev-100","key":"wrong-key"}')
    [ "$CODE" -eq 401 ] || fail "expected 401 for wrong key, got $CODE"

    curl -sf -X POST "http://127.0.0.1:$PORT/init" -H "Content-Type: application/json" \
        -d "{\"device_id\":\"dev-100\",\"key\":\"$INIT_KEY\"}" >"$WORK/init100.json"
    jget certificate <"$WORK/init100.json" >"$WORK/dev100-initial.crt"
    grep -q "BEGIN CERTIFICATE" "$WORK/dev100-initial.crt" || fail "init response missing cert"

    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/init" \
        -H "Content-Type: application/json" \
        -d "{\"device_id\":\"dev-100\",\"key\":\"$INIT_KEY\"}")
    [ "$CODE" -eq 403 ] || fail "expected 403 for duplicate init, got $CODE"

    # A device_id that would escape the certificate directory must be
    # rejected outright rather than sanitised into some other device.
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/init" \
        -H "Content-Type: application/json" \
        -d "{\"device_id\":\"../..\",\"key\":\"$INIT_KEY\"}")
    [ "$CODE" -eq 400 ] || fail "traversal device_id accepted (got $CODE)"

    # ── Test 4: POST /renew_initial_cert ──────────────────────────────
    echo "--> Test 4: POST /renew_initial_cert"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/renew_initial_cert" \
        -H "Content-Type: application/json" \
        -d "{\"device_id\":\"dev-100\",\"key\":\"$INIT_KEY\",\"initial_cert\":\"bogus-cert\"}")
    [ "$CODE" -eq 401 ] || fail "expected 401 for mismatched cert, got $CODE"

    python3 - "$WORK" "$PORT" "$INIT_KEY" <<'PY' >"$WORK/renew.json"
import json, sys, urllib.request
work, port, key = sys.argv[1], sys.argv[2], sys.argv[3]
body = json.dumps({"device_id": "dev-100", "key": key,
                   "initial_cert": open(work + "/dev100-initial.crt").read()}).encode()
req = urllib.request.Request("http://127.0.0.1:%s/renew_initial_cert" % port, data=body,
                             headers={"Content-Type": "application/json"})
sys.stdout.write(urllib.request.urlopen(req).read().decode())
PY
    jget certificate <"$WORK/renew.json" >"$WORK/dev100-renewed.crt"
    grep -q "BEGIN CERTIFICATE" "$WORK/dev100-renewed.crt" || fail "renewal missing cert"

    # ── Test 5: POST /request-cert (JSON) ─────────────────────────────
    echo "--> Test 5: POST /request-cert (JSON)"
    python3 - "$WORK" "$PORT" <<'PY' >"$WORK/op100.json"
import json, sys, urllib.request
work, port = sys.argv[1], sys.argv[2]
body = json.dumps({"device_id": "dev-100",
                   "initial_cert": open(work + "/dev100-renewed.crt").read(),
                   "validity_days": 90}).encode()
req = urllib.request.Request("http://127.0.0.1:%s/request-cert" % port, data=body,
                             headers={"Content-Type": "application/json"})
sys.stdout.write(urllib.request.urlopen(req).read().decode())
PY
    for field in certificate private_key ca_certificate expires serial algorithm; do
        [ -n "$(jget "$field" <"$WORK/op100.json")" ] || fail "request-cert missing $field"
    done
    [ "$(jget algorithm <"$WORK/op100.json")" = "$ALG" ] || fail "issued cert reports the wrong algorithm"
    jget certificate <"$WORK/op100.json" >"$WORK/dev100-op.crt"
    OP100_SERIAL=$(jget serial <"$WORK/op100.json")

    # The issued private key must not be world-readable on disk either.
    PERMS=$(stat -c '%a' "$WORK/certificates/dev-100/dev-100.key")
    [ "$PERMS" = "600" ] || fail "issued device key mode is $PERMS, expected 600"

    # ── Test 6: POST /request-cert (form POST → HTML) ─────────────────
    echo "--> Test 6: POST /request-cert (form POST)"
    curl -sf -X POST "http://127.0.0.1:$PORT/init" -H "Content-Type: application/json" \
        -d "{\"device_id\":\"dev-200\",\"key\":\"$INIT_KEY\"}" >"$WORK/init200.json"
    jget certificate <"$WORK/init200.json" >"$WORK/dev200-initial.crt"

    curl -sf -X POST "http://127.0.0.1:$PORT/request-cert" \
        --data-urlencode "device_id=dev-200" \
        --data-urlencode "initial_cert@$WORK/dev200-initial.crt" \
        --data-urlencode "validity_days=180" >"$WORK/form200.html"
    grep -q "Certificate Generated Successfully" "$WORK/form200.html" \
        || fail "HTML form cert generation failed"

    # ── Test 7: revocation and the CRL ────────────────────────────────
    echo "--> Test 7: POST /revoke & GET /crl"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/crl")
    [ "$CODE" -eq 401 ] || fail "expected 401 on /crl without key, got $CODE"

    curl -sf "http://127.0.0.1:$PORT/crl?api_key=$MGMT_KEY" >"$WORK/ca.crl.pem"
    grep -q "BEGIN X509 CRL" "$WORK/ca.crl.pem" || fail "CRL missing header"

    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/revoke" \
        -H "Content-Type: application/json" -d '{"serial":"123456"}')
    [ "$CODE" -eq 401 ] || fail "expected 401 on /revoke without key, got $CODE"

    python3 - "$WORK" "$PORT" "$MGMT_KEY" <<'PY' >"$WORK/revoke100.json"
import json, sys, urllib.request
work, port, key = sys.argv[1], sys.argv[2], sys.argv[3]
body = json.dumps({"certificate": open(work + "/dev100-op.crt").read()}).encode()
req = urllib.request.Request("http://127.0.0.1:%s/revoke" % port, data=body,
                             headers={"Content-Type": "application/json", "X-API-Key": key})
sys.stdout.write(urllib.request.urlopen(req).read().decode())
PY
    [ "$(jget status <"$WORK/revoke100.json")" = "success" ] || fail "revoke response not success"
    jget crl <"$WORK/revoke100.json" | grep -q "BEGIN X509 CRL" || fail "revoke response missing updated CRL"
    [ "$(jget serial <"$WORK/revoke100.json")" = "$OP100_SERIAL" ] || fail "revoked the wrong serial"

    # Revoking the operational certificate also invalidates dev-100's
    # enrollment, so it can no longer ask for another one.
    CODE=$(python3 - "$WORK" "$PORT" <<'PY'
import json, sys, urllib.request, urllib.error
work, port = sys.argv[1], sys.argv[2]
body = json.dumps({"device_id": "dev-100",
                   "initial_cert": open(work + "/dev100-renewed.crt").read()}).encode()
req = urllib.request.Request("http://127.0.0.1:%s/request-cert" % port, data=body,
                             headers={"Content-Type": "application/json"})
try:
    urllib.request.urlopen(req); print(200)
except urllib.error.HTTPError as e:
    print(e.code)
PY
)
    [ "$CODE" -ne 200 ] || fail "revoked device could still obtain a certificate"

    # ── Test 8: Web UI pages ──────────────────────────────────────────
    echo "--> Test 8: Web UI pages"
    curl -sf "http://127.0.0.1:$PORT/" | grep -q "Welcome to your Private PKI Service" || fail "index page"
    curl -sf "http://127.0.0.1:$PORT/request-cert" | grep -q "Request a New Certificate" || fail "request-cert page"
    curl -sf "http://127.0.0.1:$PORT/revoke" | grep -q "Revoke a Certificate" || fail "revoke page"
    curl -sf "http://127.0.0.1:$PORT/api" | grep -q "REST API Documentation" || fail "api docs page"
    curl -sf "http://127.0.0.1:$PORT/api" | grep -q "CA signature algorithm" || fail "api docs missing algorithm"
    curl -sf "http://127.0.0.1:$PORT/css/style.css" | grep -q ":root" || fail "css stylesheet"
    curl -sf "http://127.0.0.1:$PORT/js/app.js" | grep -q "copy-btn" || fail "app.js not served"

    curl -sfI "http://127.0.0.1:$PORT/" >"$WORK/head.txt"
    grep -qi "content-security-policy:.*script-src 'self'" "$WORK/head.txt" || fail "missing CSP"
    grep -qi "x-content-type-options: nosniff" "$WORK/head.txt" || fail "missing nosniff"
    grep -qi "frame-ancestors 'none'" "$WORK/head.txt" || fail "missing frame-ancestors"

    # ── Test 9: security regressions ──────────────────────────────────
    echo "--> Test 9: security regressions"

    # 9a. A serial is echoed into HTML — it must be validated, and what
    #     does get echoed must be escaped.
    curl -s -X POST "http://127.0.0.1:$PORT/revoke" \
        --data-urlencode "api_key=$MGMT_KEY" \
        --data-urlencode 'serial=<script>alert(1)</script>' >"$WORK/xss.html"
    grep -q "<script>alert(1)</script>" "$WORK/xss.html" && fail "reflected XSS via serial"
    grep -q "Error:" "$WORK/xss.html" || fail "malformed serial was not rejected"

    # 9b. index.txt is tab-separated — a serial carrying tabs or
    #     newlines must not be able to forge revocation records.
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/revoke" \
        -H "Content-Type: application/json" -H "X-API-Key: $MGMT_KEY" \
        -d '{"serial":"deadbeef\tinjected\nR\tx\tx\tcafebabe\tunknown\t/CN=pwn"}')
    [ "$CODE" -eq 400 ] || fail "index.txt injection via serial accepted (got $CODE)"
    grep -q "cafebabe" "$WORK/index.txt" && fail "forged record landed in index.txt"

    # 9c. Revoking used to trust the CN of an unverified certificate and
    #     then use it to name a file. A self-signed certificate carrying
    #     a traversing SAN must be refused before any of that.
    mkdir -p "$WORK/escape-probe"
    openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/evil.key" 2>/dev/null
    openssl req -new -x509 -key "$WORK/evil.key" -out "$WORK/evil.crt" -days 2 \
        -subj "/CN=evil" -addext "subjectAltName=DNS:../escape-probe" 2>/dev/null
    CODE=$(python3 - "$WORK" "$PORT" "$MGMT_KEY" <<'PY'
import json, sys, urllib.request, urllib.error
work, port, key = sys.argv[1], sys.argv[2], sys.argv[3]
body = json.dumps({"certificate": open(work + "/evil.crt").read()}).encode()
req = urllib.request.Request("http://127.0.0.1:%s/revoke" % port, data=body,
                             headers={"Content-Type": "application/json", "X-API-Key": key})
try:
    urllib.request.urlopen(req); print(200)
except urllib.error.HTTPError as e:
    print(e.code)
PY
)
    [ "$CODE" -eq 400 ] || fail "certificate from a foreign CA accepted for revocation (got $CODE)"
    [ ! -e "$WORK/initial/escape-probe.crt" ] || fail "path traversal wrote outside --initial-dir"

    # 9d. Revoking by serial alone leaves no CN to invalidate a file
    #     by, so the enrollment gate has to consult index.txt.
    curl -sf -X POST "http://127.0.0.1:$PORT/init" -H "Content-Type: application/json" \
        -d "{\"device_id\":\"dev-300\",\"key\":\"$INIT_KEY\"}" >"$WORK/init300.json"
    jget certificate <"$WORK/init300.json" >"$WORK/dev300-initial.crt"
    SER300=$(openssl x509 -in "$WORK/dev300-initial.crt" -noout -serial | cut -d= -f2 | tr 'A-F' 'a-f')
    curl -sf -o /dev/null -X POST "http://127.0.0.1:$PORT/revoke" \
        -H "Content-Type: application/json" -H "X-API-Key: $MGMT_KEY" \
        -d "{\"serial\":\"$SER300\"}"
    CODE=$(python3 - "$WORK" "$PORT" <<'PY'
import json, sys, urllib.request, urllib.error
work, port = sys.argv[1], sys.argv[2]
body = json.dumps({"device_id": "dev-300",
                   "initial_cert": open(work + "/dev300-initial.crt").read()}).encode()
req = urllib.request.Request("http://127.0.0.1:%s/request-cert" % port, data=body,
                             headers={"Content-Type": "application/json"})
try:
    urllib.request.urlopen(req); print(200)
except urllib.error.HTTPError as e:
    print(e.code)
PY
)
    [ "$CODE" -eq 403 ] || fail "serial-only revocation did not lock the device out (got $CODE)"

    # ── Test 10: PKCS#10 CSR issuance ─────────────────────────────────
    echo "--> Test 10: POST /request-csr"
    openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/client.key" 2>/dev/null
    openssl req -new -key "$WORK/client.key" -out "$WORK/client.csr" \
        -subj "/CN=edge-device-500" -addext "subjectAltName=DNS:edge-device-500" 2>/dev/null

    CODE=$(python3 - "$WORK" "$PORT" <<'PY'
import json, sys, urllib.request, urllib.error
work, port = sys.argv[1], sys.argv[2]
body = json.dumps({"csr": open(work + "/client.csr").read()}).encode()
req = urllib.request.Request("http://127.0.0.1:%s/request-csr" % port, data=body,
                             headers={"Content-Type": "application/json"})
try:
    urllib.request.urlopen(req); print(200)
except urllib.error.HTTPError as e:
    print(e.code)
PY
)
    [ "$CODE" -eq 401 ] || fail "/request-csr served an unauthenticated caller (got $CODE)"

    python3 - "$WORK" "$PORT" "$MGMT_KEY" <<'PY' >"$WORK/csr.json"
import json, sys, urllib.request
work, port, key = sys.argv[1], sys.argv[2], sys.argv[3]
body = json.dumps({"csr": open(work + "/client.csr").read(), "validity_days": 365}).encode()
req = urllib.request.Request("http://127.0.0.1:%s/request-csr" % port, data=body,
                             headers={"Content-Type": "application/json", "X-API-Key": key})
sys.stdout.write(urllib.request.urlopen(req).read().decode())
PY
    [ "$(jget status <"$WORK/csr.json")" = "success" ] || fail "request-csr not success"
    jget certificate <"$WORK/csr.json" >"$WORK/client.crt"
    # The subject key stays whatever the requester generated (EC here),
    # while the issuer signature follows the CA.
    openssl x509 -in "$WORK/client.crt" -noout -text 2>/dev/null | grep -q "id-ecPublicKey" \
        || fail "CSR-issued cert lost the requester's EC key"

    # A tampered CSR must not pass its own self-signature check.
    python3 - "$WORK" >"$WORK/bad.csr" <<'PY'
import base64, sys
work = sys.argv[1]
pem = open(work + "/client.csr").read().strip().splitlines()
der = bytearray(base64.b64decode("".join(pem[1:-1])))
der[40] ^= 0x01          # flip a bit inside CertificationRequestInfo
body = base64.b64encode(bytes(der)).decode()
print("-----BEGIN CERTIFICATE REQUEST-----")
for i in range(0, len(body), 64):
    print(body[i:i + 64])
print("-----END CERTIFICATE REQUEST-----")
PY
    CODE=$(python3 - "$WORK" "$PORT" "$MGMT_KEY" <<'PY'
import json, sys, urllib.request, urllib.error
work, port, key = sys.argv[1], sys.argv[2], sys.argv[3]
body = json.dumps({"csr": open(work + "/bad.csr").read()}).encode()
req = urllib.request.Request("http://127.0.0.1:%s/request-csr" % port, data=body,
                             headers={"Content-Type": "application/json", "X-API-Key": key})
try:
    urllib.request.urlopen(req); print(200)
except urllib.error.HTTPError as e:
    print(e.code)
PY
)
    [ "$CODE" -eq 400 ] || fail "tampered CSR was signed anyway (got $CODE)"

    # ── Test 11: DER / OpenSSL interop ────────────────────────────────
    echo "--> Test 11: DER structure and OpenSSL interop"
    openssl asn1parse -in "$WORK/ca.crt" -inform PEM >/dev/null 2>&1 || fail "CA cert is not well-formed DER"
    openssl asn1parse -in "$WORK/dev100-op.crt" -inform PEM >/dev/null 2>&1 || fail "issued cert is not well-formed DER"
    openssl asn1parse -in "$WORK/ca.crl.pem" -inform PEM >/dev/null 2>&1 || fail "CRL is not well-formed DER"
    openssl crl -in "$WORK/ca.crl.pem" -noout -text >/dev/null 2>&1 || fail "OpenSSL cannot parse the CRL"

    openssl x509 -in "$WORK/ca.crt" -noout -text 2>/dev/null | grep -q "CA:TRUE" \
        || fail "CA cert missing basicConstraints CA:TRUE"
    openssl x509 -in "$WORK/ca.crt" -noout -text 2>/dev/null | grep -q "Certificate Sign" \
        || fail "CA cert missing keyCertSign"
    openssl x509 -in "$WORK/dev100-op.crt" -noout -text 2>/dev/null | grep -q "CA:FALSE" \
        || fail "leaf cert missing basicConstraints CA:FALSE"
    openssl x509 -in "$WORK/dev100-op.crt" -noout -text 2>/dev/null | grep -q "Authority Key Identifier" \
        || fail "leaf cert missing authorityKeyIdentifier"

    if [ "$ALG" = "p256" ]; then
        openssl verify -CAfile "$WORK/ca.crt" "$WORK/dev100-op.crt" >/dev/null 2>&1 \
            || fail "OpenSSL chain verification of the issued cert failed"
        openssl verify -CAfile "$WORK/ca.crt" "$WORK/client.crt" >/dev/null 2>&1 \
            || fail "OpenSSL chain verification of the CSR-issued cert failed"
        echo "    OpenSSL chain verification: OK"
    else
        # OpenSSL < 3.5 has no ML-DSA, so a chain build is not available
        # here; the signature is verified by the in-process smoke tests.
        openssl x509 -in "$WORK/ca.crt" -noout -text 2>/dev/null \
            | grep -q "2.16.840.1.101.3.4.3.18" || fail "PQ CA is not ML-DSA-65"
        echo "    ML-DSA OIDs present; chain verify skipped (OpenSSL $(openssl version -v | cut -d' ' -f2) has no ML-DSA)"
    fi

    # ── Test 12: CA survives a restart ────────────────────────────────
    echo "--> Test 12: CA reload across restart"
    CA_BEFORE=$(sha256sum "$WORK/ca.crt" | cut -d' ' -f1)
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""

    "$BIN" --port "$PORT" --host 127.0.0.1 --algorithm p256 \
        --ca-cert "$WORK/ca.crt" --ca-key "$WORK/ca.key" \
        --crl-file "$WORK/ca.crl" --index-file "$WORK/index.txt" \
        --initial-dir "$WORK/initial" --certs-dir "$WORK/certificates" \
        --init-key "$INIT_KEY" --mgmt-key "$MGMT_KEY" \
        --ca-cn "Test PKI Root CA" >"$WORK/server2.log" 2>&1 &
    SERVER_PID=$!
    for _ in $(seq 1 200); do
        curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
        sleep 0.1
    done
    CA_AFTER=$(sha256sum "$WORK/ca.crt" | cut -d' ' -f1)
    [ "$CA_BEFORE" = "$CA_AFTER" ] || fail "restart replaced the existing CA certificate"
    # --algorithm names what a NEW CA is minted with; an existing CA
    # keeps its own, so this restart must still report $ALG.
    curl -sf "http://127.0.0.1:$PORT/health" >"$WORK/health2.json"
    [ "$(jget algorithm <"$WORK/health2.json")" = "$ALG" ] \
        || fail "restart changed the CA algorithm to $(jget algorithm <"$WORK/health2.json")"

    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
}

BASE_PORT=$(( 18000 + ( $$ % 900 ) ))
run_suite p256    "$BASE_PORT"
run_suite mldsa65 "$(( BASE_PORT + 1 ))"

echo ""
echo "=================================================="
echo "  ALL E2E INTEGRATION TESTS PASSED SUCCESSFULLY!  "
echo "=================================================="
