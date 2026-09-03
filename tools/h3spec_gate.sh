#!/usr/bin/env bash
# ============================================================
#  tools/h3spec_gate.sh — HTTP/3 conformance gate (h3spec: QUIC RFC 9000/
#  9001 + HTTP/3 RFC 9114 + QPACK RFC 9204)
#
#  Runs h3spec 0.1.13 — kazu-yamamoto's QUIC/HTTP/3 error-case suite —
#  against the SAME HttpApp binary the HTTP/2 gate uses
#  (tools/h2spec/server.nu): one TLS listener on 127.0.0.1:PORT that is
#  also bound over UDP on that port and served as HTTP/3 (that is what
#  `http_app_listen_tls` does by default). Fails unless h3spec reports
#
#      49 examples, 0 failures
#
#  (34 "QUIC servers" + 15 "HTTP/3 servers" cases; the 0-RTT case is one
#  of the 49 and passes against a server that offers no early data).
#  Every assertion greps for the POSITIVE totals line: an h3spec that
#  could not reach the server prints no such line and fails the gate
#  instead of passing it silently.
#
#  Then the TCP side of the same listener must announce the QUIC side:
#  `curl --http2` and `curl --http1.1` responses carry
#  `alt-svc: h3=":PORT"`. When a docker daemon and the ymuski/curl-http3
#  image are available, an actual `curl --http3-only` request must come
#  back `3 200` (skipped with a loud line otherwise — the host's curl has
#  no HTTP/3).
#
#  Tools: build/nurlc, h3spec (PATH, $H3SPEC, or ~/.local/bin), openssl
#  (self-signed P-256 cert), curl (TCP checks), docker (optional).
#
#  Usage:  ./tools/h3spec_gate.sh          (from the repo root)
#  Exit:   0 = every expectation met · 1 = a deviation · 2 = tooling
# ============================================================
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

H3SPEC="${H3SPEC:-$(command -v h3spec 2>/dev/null || true)}"
[[ -x "$H3SPEC" ]] || H3SPEC="$HOME/.local/bin/h3spec"
if [[ ! -x "$H3SPEC" ]]; then
    echo "h3spec_gate: h3spec not found (PATH, \$H3SPEC, ~/.local/bin)" >&2
    exit 2
fi
for tool in openssl curl; do
    command -v "$tool" >/dev/null || { echo "h3spec_gate: $tool not found" >&2; exit 2; }
done
[[ -x build/nurlc ]] || { echo "h3spec_gate: build/nurlc missing — run ./build.sh" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/h3spec-gate.XXXXXX")"
PIDS=()
cleanup() {
    for p in "${PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null; done
    sleep 0.3
    for p in "${PIDS[@]:-}"; do [[ -n "$p" ]] && kill -9 "$p" 2>/dev/null; done
    rm -rf "$WORK"
}
trap cleanup EXIT

PORT="${H3_PORT:-18474}"
EXPECT="49 examples, 0 failures"

echo "h3spec_gate: h3spec $("$H3SPEC" -v 2>&1 | head -1)"

# ── build ───────────────────────────────────────────────────────────
./nurl.sh tools/h2spec/server.nu "$WORK/server" >"$WORK/build_server.log" 2>&1 \
    || { echo "h3spec_gate: building tools/h2spec/server.nu failed:" >&2; cat "$WORK/build_server.log" >&2; exit 2; }
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 2 -subj "/CN=localhost" \
    -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" >/dev/null 2>&1 \
    || { echo "h3spec_gate: openssl could not mint a cert" >&2; exit 2; }

wait_port() {   # wait_port PORT — until something accepts on 127.0.0.1:PORT (TCP)
    local i
    for i in $(seq 1 100); do
        if (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; then exec 3>&- 2>/dev/null; return 0; fi
        sleep 0.05
    done
    echo "h3spec_gate: nothing listening on 127.0.0.1:$1" >&2
    return 1
}

FAIL=0

"$WORK/server" "$PORT" "$WORK/cert.pem" "$WORK/key.pem" >"$WORK/server.log" 2>&1 &
PIDS+=($!)
wait_port "$PORT" || { cat "$WORK/server.log" >&2; exit 2; }
if grep -q "HTTP/3 off" "$WORK/server.log"; then
    echo "  FAIL the server did not bring up HTTP/3:"; cat "$WORK/server.log"; FAIL=1
fi

# ── 1. h3spec: QUIC transport + HTTP/3 + QPACK, 49 cases ────────────
echo "1. h3spec against HttpApp TLS+UDP (127.0.0.1:$PORT)"
"$H3SPEC" 127.0.0.1 "$PORT" -n -t 4000 >"$WORK/h3spec.txt" 2>&1
sed -e 's/\x1b\[[0-9;]*m//g' "$WORK/h3spec.txt" >"$WORK/h3spec.clean"
if grep -qF "$EXPECT" "$WORK/h3spec.clean" \
   && grep -q '^QUIC servers' "$WORK/h3spec.clean" \
   && grep -q '^HTTP/3 servers' "$WORK/h3spec.clean"; then
    echo "  ok   h3spec — $EXPECT (QUIC servers + HTTP/3 servers groups both ran)"
else
    echo "  FAIL h3spec — expected '$EXPECT', got: $(grep -E '^[0-9]+ examples,' "$WORK/h3spec.clean" | tail -1 || echo '<no totals line — h3spec did not run>')"
    grep -E '✘' "$WORK/h3spec.clean" | head -20
    grep -A6 '^  [0-9]+) ' "$WORK/h3spec.clean" | head -60
    FAIL=1
fi

# ── 2. the TCP side announces the QUIC side ─────────────────────────
echo "2. Alt-Svc on the TCP responses of the same listener"
for proto in http2 http1.1; do
    hdrs="$(curl -sk -D - -o /dev/null "--$proto" "https://127.0.0.1:$PORT/")"
    if echo "$hdrs" | grep -qiE "^alt-svc: *h3=\":$PORT\""; then
        echo "  ok   curl --$proto → alt-svc: h3=\":$PORT\""
    else
        echo "  FAIL curl --$proto → no alt-svc header; got:"; echo "$hdrs" | head -10; FAIL=1
    fi
done

# ── 3. an HTTP/3 request end to end (docker curl-http3, when present) ─
echo "3. curl --http3-only (docker ymuski/curl-http3)"
if command -v docker >/dev/null && docker image inspect ymuski/curl-http3 >/dev/null 2>&1; then
    v_h3="$(timeout 20 docker run --rm --network=host ymuski/curl-http3 \
              curl -sk -m 8 --http3-only -o /dev/null -w '%{http_version} %{http_code}' \
              "https://127.0.0.1:$PORT/" 2>/dev/null || true)"
    if [[ "$v_h3" == "3 200" ]]; then
        echo "  ok   curl --http3-only → 3 200"
    else
        echo "  FAIL curl --http3-only → '$v_h3' (want '3 200')"; FAIL=1
    fi
else
    echo "  SKIP docker or the ymuski/curl-http3 image is not available on this host"
fi

if [[ "$FAIL" == 0 ]]; then
    echo "h3spec_gate: PASS — h3spec $EXPECT over HttpApp TLS+UDP; Alt-Svc on HTTP/1.1 and HTTP/2"
    exit 0
fi
echo "h3spec_gate: FAIL"
echo "--- server log ---"; cat "$WORK/server.log"
exit 1
