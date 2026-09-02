#!/usr/bin/env bash
# ============================================================
#  tools/h2spec_gate.sh — HTTP/2 conformance gate (h2spec, RFC 9113 + 7541)
#
#  Runs h2spec 2.6.0 — the reference HTTP/2 conformance suite — against
#  the NURL HTTP server in the three ways a client reaches HTTP/2, and
#  fails unless every run reports exactly the expected totals:
#
#    1. HttpApp over TLS, "h2" negotiated by ALPN (RFC 9113 §3.3)
#         h2spec -t -k        146/146   strict (-S) 147/147
#    2. an HTTP/2-only endpoint (examples/h2c_server.nu, http2_serve)
#         h2spec              146/146   strict (-S) 147/147
#    3. HttpApp on a plaintext port shared with HTTP/1.1, prior knowledge
#       (RFC 9113 §3.4)
#         h2spec              145/146   strict (-S) 146/147
#       with §3.5/2 "Sends invalid connection preface" the ONE failure:
#       on a dual-protocol port a first line that is neither the preface
#       nor HTTP is an HTTP/1.1 request with a bad request line and gets
#       HTTP/1.1's 400 — there is no HTTP/2 connection to send a GOAWAY on.
#       The gate pins that failure by name: any other failure, or that one
#       passing (which would mean HTTP/1.1 stopped being served there), is
#       a regression.
#
#  Then curl (nghttp2) confirms the negotiated protocol end to end:
#  `--http2-prior-knowledge` → HTTP/2, `--http2` over https → HTTP/2,
#  `--http1.1` over https → HTTP/1.1 on the same listener.
#
#  Every assertion greps for the POSITIVE totals line ("146 tests, 146
#  passed, 0 skipped, 0 failed"): an h2spec that could not connect prints
#  nothing of the kind and fails the gate instead of passing it silently.
#
#  h2spec's release binary is Go 1.12, whose TLS client offers TLS 1.2
#  only unless GODEBUG=tls13=1; the pure-NURL server is TLS 1.3 only, so
#  the TLS runs set it. Tools: build/nurlc, h2spec (PATH, $H2SPEC, or
#  ~/.local/bin), openssl (self-signed P-256 cert), curl with HTTP/2.
#
#  Usage:  ./tools/h2spec_gate.sh          (from the repo root)
#  Exit:   0 = every expectation met · 1 = a deviation · 2 = tooling
# ============================================================
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

H2SPEC="${H2SPEC:-$(command -v h2spec 2>/dev/null || true)}"
[[ -x "$H2SPEC" ]] || H2SPEC="$HOME/.local/bin/h2spec"
if [[ ! -x "$H2SPEC" ]]; then
    echo "h2spec_gate: h2spec not found (PATH, \$H2SPEC, ~/.local/bin)" >&2
    exit 2
fi
for tool in openssl curl; do
    command -v "$tool" >/dev/null || { echo "h2spec_gate: $tool not found" >&2; exit 2; }
done
[[ -x build/nurlc ]] || { echo "h2spec_gate: build/nurlc missing — run ./build.sh" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/h2spec-gate.XXXXXX")"
PIDS=()
cleanup() {
    for p in "${PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null; done
    sleep 0.2
    for p in "${PIDS[@]:-}"; do [[ -n "$p" ]] && kill -9 "$p" 2>/dev/null; done
    rm -rf "$WORK"
}
trap cleanup EXIT

PLAIN_PORT="${PLAIN_PORT:-18471}"
TLS_PORT="${TLS_PORT:-18472}"
H2C_PORT=8443              # examples/h2c_server.nu binds this itself

echo "h2spec_gate: $("$H2SPEC" --version 2>&1 | head -1)"

# ── build ───────────────────────────────────────────────────────────
./nurl.sh tools/h2spec/server.nu "$WORK/server" >"$WORK/build_server.log" 2>&1 \
    || { echo "h2spec_gate: building tools/h2spec/server.nu failed:" >&2; cat "$WORK/build_server.log" >&2; exit 2; }
./nurl.sh examples/h2c_server.nu "$WORK/h2c_server" >"$WORK/build_h2c.log" 2>&1 \
    || { echo "h2spec_gate: building examples/h2c_server.nu failed:" >&2; cat "$WORK/build_h2c.log" >&2; exit 2; }
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 2 -subj "/CN=localhost" \
    -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" >/dev/null 2>&1 \
    || { echo "h2spec_gate: openssl could not mint a cert" >&2; exit 2; }

wait_port() {   # wait_port PORT — until something accepts on 127.0.0.1:PORT
    local i
    for i in $(seq 1 100); do
        if (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; then exec 3>&- 2>/dev/null; return 0; fi
        sleep 0.05
    done
    echo "h2spec_gate: nothing listening on 127.0.0.1:$1" >&2
    return 1
}

FAIL=0
expect_totals() {   # expect_totals LABEL LOGFILE "N tests, M passed, 0 skipped, K failed"
    if grep -qF "$3" "$2"; then
        echo "  ok   $1 — $3"
    else
        echo "  FAIL $1 — expected '$3', got: $(grep -E '^[0-9]+ tests,' "$2" | tail -1 || echo '<no totals line — h2spec did not run>')"
        grep -B1 -A6 '×' "$2" | head -40
        FAIL=1
    fi
}

# ── 1. HttpApp over TLS + ALPN ──────────────────────────────────────
"$WORK/server" "$TLS_PORT" "$WORK/cert.pem" "$WORK/key.pem" >"$WORK/tls_server.log" 2>&1 &
PIDS+=($!)
wait_port "$TLS_PORT" || exit 2
echo "1. HttpApp, TLS + ALPN h2 (127.0.0.1:$TLS_PORT)"
GODEBUG=tls13=1 "$H2SPEC" -t -k -h 127.0.0.1 -p "$TLS_PORT" -o 3 >"$WORK/tls.txt" 2>&1
expect_totals "tls" "$WORK/tls.txt" "146 tests, 146 passed, 0 skipped, 0 failed"
GODEBUG=tls13=1 "$H2SPEC" -S -t -k -h 127.0.0.1 -p "$TLS_PORT" -o 3 >"$WORK/tls_strict.txt" 2>&1
expect_totals "tls strict" "$WORK/tls_strict.txt" "147 tests, 147 passed, 0 skipped, 0 failed"

# curl: protocol actually negotiated, end to end
v_h2="$(curl -sk -o /dev/null -w '%{http_version} %{http_code}' --http2 "https://127.0.0.1:$TLS_PORT/")"
v_h1="$(curl -sk -o /dev/null -w '%{http_version} %{http_code}' --http1.1 "https://127.0.0.1:$TLS_PORT/")"
[[ "$v_h2" == "2 200" ]]   && echo "  ok   curl --http2 over TLS → $v_h2"   || { echo "  FAIL curl --http2 over TLS → '$v_h2' (want '2 200')"; FAIL=1; }
[[ "$v_h1" == "1.1 200" ]] && echo "  ok   curl --http1.1 over TLS → $v_h1" || { echo "  FAIL curl --http1.1 over TLS → '$v_h1' (want '1.1 200')"; FAIL=1; }

# ── 2. HTTP/2-only endpoint (http2_serve) ───────────────────────────
"$WORK/h2c_server" >"$WORK/h2c_server.log" 2>&1 &
PIDS+=($!)
wait_port "$H2C_PORT" || exit 2
echo "2. examples/h2c_server.nu, HTTP/2-only h2c (127.0.0.1:$H2C_PORT)"
"$H2SPEC" -h 127.0.0.1 -p "$H2C_PORT" -o 3 >"$WORK/h2c.txt" 2>&1
expect_totals "h2c" "$WORK/h2c.txt" "146 tests, 146 passed, 0 skipped, 0 failed"
"$H2SPEC" -S -h 127.0.0.1 -p "$H2C_PORT" -o 3 >"$WORK/h2c_strict.txt" 2>&1
expect_totals "h2c strict" "$WORK/h2c_strict.txt" "147 tests, 147 passed, 0 skipped, 0 failed"

# ── 3. HttpApp plaintext, shared with HTTP/1.1, prior knowledge ─────
"$WORK/server" "$PLAIN_PORT" >"$WORK/plain_server.log" 2>&1 &
PIDS+=($!)
wait_port "$PLAIN_PORT" || exit 2
echo "3. HttpApp, plaintext shared port, prior knowledge (127.0.0.1:$PLAIN_PORT)"
"$H2SPEC" -h 127.0.0.1 -p "$PLAIN_PORT" -o 3 >"$WORK/plain.txt" 2>&1
expect_totals "plain" "$WORK/plain.txt" "146 tests, 145 passed, 0 skipped, 1 failed"
"$H2SPEC" -S -h 127.0.0.1 -p "$PLAIN_PORT" -o 3 >"$WORK/plain_strict.txt" 2>&1
expect_totals "plain strict" "$WORK/plain_strict.txt" "147 tests, 146 passed, 0 skipped, 1 failed"
for f in plain plain_strict; do
    if [[ "$(grep -c '×' "$WORK/$f.txt")" == "2" ]] && grep -q '× 2: Sends invalid connection preface' "$WORK/$f.txt"; then
        echo "  ok   $f — the one failure is §3.5/2 (invalid preface → HTTP/1.1 400 on a shared port)"
    else
        echo "  FAIL $f — the failure set is not exactly §3.5/2:"; grep '×' "$WORK/$f.txt" | sort -u; FAIL=1
    fi
done
v_pk="$(curl -s -o /dev/null -w '%{http_version} %{http_code}' --http2-prior-knowledge "http://127.0.0.1:$PLAIN_PORT/")"
v_11="$(curl -s -o /dev/null -w '%{http_version} %{http_code}' "http://127.0.0.1:$PLAIN_PORT/")"
[[ "$v_pk" == "2 200" ]]   && echo "  ok   curl --http2-prior-knowledge → $v_pk" || { echo "  FAIL curl --http2-prior-knowledge → '$v_pk' (want '2 200')"; FAIL=1; }
[[ "$v_11" == "1.1 200" ]] && echo "  ok   curl HTTP/1.1 on the same port → $v_11" || { echo "  FAIL curl HTTP/1.1 same port → '$v_11' (want '1.1 200')"; FAIL=1; }

if (( FAIL )); then
    echo "h2spec_gate: FAIL"
    exit 1
fi
echo "h2spec_gate: PASS — h2spec 146/146 (+strict 147/147) over TLS+ALPN and h2c; shared plaintext port 145/146 with §3.5/2 as designed"
