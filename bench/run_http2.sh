#!/usr/bin/env bash
# bench/run_http2.sh — HTTP/2 peer-comparison benchmark (h2c + h2 over TLS).
#
# The HTTP/2 sibling of bench/run_http.sh. That script and its report
# (bench/HTTP_RESULTS.md) stay HTTP/1.1-only and are not touched by this
# one; the two are meant to be read side by side.
#
# For each available HTTP/2 server implementation (NURL / Rust hyper /
# Node http2), and for BOTH a cleartext listener (h2c, RFC 9113 §3.4
# prior knowledge) and a TLS listener (ALPN "h2", §3.3), this script:
#   1. Builds / preps the server binary
#   2. Starts it on its dedicated loopback port (cleartext, then TLS)
#   3. Waits until the listener accepts (small TCP probe loop)
#   4. For every cell "CxP" in $CELLS runs `oha --http2` for $DURATION
#      seconds with C connections and P concurrent streams per connection
#      (C*P requests in flight); TLS runs add `--insecure` for the
#      self-signed bench cert
#   5. Kills the server
#   6. Captures requests/sec, p50 and p99 latency from oha's JSON
#
# The NURL server additionally gets an HTTP/1.1 reference row at P=1 —
# the same binary, the same listener, `oha` without `--http2` — so the
# protocol's own cost is visible on one line of the report.
#
# It then OVERWRITES bench/HTTP2_RESULTS.md with a fully generated report.
# That file is 100% generated — do not edit it by hand; the next run
# replaces it. Same contract as HTTP_RESULTS.md / RESULTS.md.
#
# Usage:
#   bench/run_http2.sh                        # defaults (see below)
#   DURATION=20 CELLS="1x1 10x10" bench/run_http2.sh
#   bench/run_http2.sh --cells "1x1 1x10 50x10"
#   bench/run_http2.sh --md /tmp/out.md       # write elsewhere
#
# Tools detected: nurlc (./build/), cargo (rust hyper), node, oha,
# openssl (for the self-signed TLS cert). Missing tools are reported
# "n/a" in the table.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH="$ROOT/bench"

DURATION="${DURATION:-10}"               # seconds per cell
CELLS="${CELLS:-1x1 1x10 1x100 10x1 10x10 50x1 50x10}"   # connections x streams
SETTLE_MS="${SETTLE_MS:-500}"            # post-start spin-up before bench
KILL_WAIT="${KILL_WAIT:-1}"              # post-bench grace before SIGKILL
ITERS="${ITERS:-3}"                      # measurement runs per cell, median wins
MD_OUT="${MD_OUT:-$BENCH/HTTP2_RESULTS.md}"

while (( $# > 0 )); do
    case "$1" in
        --cells)    CELLS="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --md)       MD_OUT="$2"; shift 2 ;;
        *)          echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# ── tool detection ──────────────────────────────────────────────────
NURLC="$ROOT/build/nurlc"
RUNTIME="$ROOT/stdlib/runtime.o"
OHA="${OHA:-$HOME/.cargo/bin/oha}"
[[ -x "$OHA" ]] || OHA="$(command -v oha 2>/dev/null || true)"
if [[ -z "$OHA" || ! -x "$OHA" ]]; then
    echo "ERROR: oha not found. Install with: cargo install oha --version 1.8.0 --locked" >&2
    exit 2
fi
OHA_VERSION="$($OHA --version 2>&1 | head -1)"
echo "# oha: $OHA_VERSION" >&2

have_nurl=0; [[ -x "$NURLC" && -f "$RUNTIME" ]] && have_nurl=1
have_rs=0;   command -v cargo >/dev/null && have_rs=1
have_js=0;   command -v node  >/dev/null && have_js=1
have_ssl=0;  command -v openssl >/dev/null && have_ssl=1

# Self-signed EC P-256 cert. Its own file pair, so this run never rewrites
# the one bench/run_http.sh generates.
TLS_CERT="$BENCH/_build/tls2-cert.pem"
TLS_KEY="$BENCH/_build/tls2-key.pem"
have_tls=0
if (( have_ssl )); then
    mkdir -p "$BENCH/_build"
    if openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -nodes -keyout "$TLS_KEY" -out "$TLS_CERT" -days 3650 \
        -subj "/CN=localhost" \
        -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" >/dev/null 2>&1; then
        have_tls=1
    else
        echo "# WARNING: openssl could not generate a cert — TLS rows will be n/a" >&2
    fi
else
    echo "# WARNING: openssl not found — TLS rows will be n/a" >&2
fi

# ── environment for the report header ───────────────────────────────
NURL_VERSION="$("$NURLC" --version 2>/dev/null | head -1)"
[[ -n "$NURL_VERSION" ]] || NURL_VERSION="$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null)"
RUSTC_VERSION="$(command -v rustc >/dev/null && rustc --version || echo 'n/a')"
NODE_VERSION="$(command -v node >/dev/null && node --version || echo 'n/a')"
HOST_KERNEL="$(uname -srm)"
HOST_CPU="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //')"
[[ -n "$HOST_CPU" ]] || HOST_CPU="$(uname -p)"
HOST_CORES="$(nproc 2>/dev/null || echo 0)"
HOST_MEM_KB="$(grep -m1 MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')"
[[ -n "$HOST_MEM_KB" ]] || HOST_MEM_KB=0
HOST_LABEL="${BENCH_HOST_LABEL:-$(uname -s) $(uname -m)}"
COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
RUN_URL="${BENCH_RUN_URL:-}"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── helpers ─────────────────────────────────────────────────────────
wait_listen() {
    local port="$1"
    local i
    for i in $(seq 1 60); do
        if (echo > "/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
            return 0
        fi
        sleep 0.05
    done
    return 1
}

stop_pid() {
    local pid="$1"
    [[ -z "$pid" ]] && return 0
    kill -TERM "$pid" 2>/dev/null || true
    local i
    for i in $(seq 1 $((KILL_WAIT * 10))); do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.1
    done
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

# oha JSON → "rps p50_ms p99_ms mean_ms" (or FAILs when <99 % succeeded).
_parse_oha() {
    python3 - "$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        r = json.load(f)
except Exception:
    print("FAIL FAIL FAIL FAIL"); raise SystemExit
summary = r.get("summary", {})
if (summary.get("successRate", 0.0) or 0.0) < 0.99:
    print("FAIL FAIL FAIL FAIL"); raise SystemExit
rps = summary.get("requestsPerSec", 0.0) or 0.0
mean = summary.get("average", 0.0) or 0.0
lat = r.get("latencyPercentiles", {})
def ms(v):
    return (v * 1000.0) if isinstance(v, (int, float)) else 0.0
print(f"{rps:.0f} {ms(lat.get('p50')):.2f} {ms(lat.get('p99')):.2f} {mean*1000.0:.4f}")
PY
}

# One measured cell. proto = h2 | h1 (h1 = the HTTP/1.1 reference run).
run_oha() {
    local proto="$1" scheme="$2" port="$3" conns="$4" streams="$5"
    local report="$BENCH/_build/oha2-$proto-$scheme-$port-c$conns-p$streams.json"
    local flags=()
    [[ "$scheme" == https ]] && flags+=(--insecure)
    [[ "$proto" == h2 ]] && flags+=(--http2 -p "$streams")
    mkdir -p "$BENCH/_build"
    # short warm-up, then the timed run
    "$OHA" --no-tui "${flags[@]}" -n 1000 -c "$conns" \
        "$scheme://127.0.0.1:$port/" >/dev/null 2>&1 || true
    "$OHA" --no-tui "${flags[@]}" -j -z "${DURATION}s" -c "$conns" \
        "$scheme://127.0.0.1:$port/" > "$report" 2>/dev/null \
        || { echo "FAIL FAIL FAIL FAIL"; return; }
    _parse_oha "$report"
}

median() {   # median of the numbers on argv, printed with 2 decimals
    python3 -c "
import sys
vals=sorted(float(x) for x in sys.argv[1:])
m=vals[len(vals)//2] if len(vals)%2 else (vals[len(vals)//2-1]+vals[len(vals)//2])/2
print(f'{m:.2f}')" "$@"
}
median_int() {
    python3 -c "
import sys
vals=sorted(float(x) for x in sys.argv[1:])
m=vals[len(vals)//2] if len(vals)%2 else (vals[len(vals)//2-1]+vals[len(vals)//2])/2
print(int(round(m)))" "$@"
}

# Run ITERS measurements of one cell and print the median row, or FAIL.
# Prints: "<prefix> rps p50 p99 mean"
measure_cell() {
    local proto="$1" scheme="$2" port="$3" conns="$4" streams="$5"
    local rps_list=() p50_list=() p99_list=() mean_list=() i
    for i in $(seq 1 "$ITERS"); do
        local r rps p50 p99 mean
        r=$(run_oha "$proto" "$scheme" "$port" "$conns" "$streams")
        read -r rps p50 p99 mean <<<"$r"
        if [[ "$rps" == "FAIL" ]]; then
            echo "FAIL FAIL FAIL FAIL"
            return
        fi
        rps_list+=("$rps"); p50_list+=("$p50"); p99_list+=("$p99"); mean_list+=("$mean")
    done
    echo "$(median_int "${rps_list[@]}") $(median "${p50_list[@]}") $(median "${p99_list[@]}") $(median "${mean_list[@]}")"
}

# ── servers ─────────────────────────────────────────────────────────
# The NURL peer is bench/http_server.nu unchanged — the HttpApp facade
# serves HTTP/2 on every listener (ALPN h2 over TLS, prior knowledge on
# cleartext), so the very binary run_http.sh measures over HTTP/1.1 is the
# one measured here over HTTP/2.
NURL_BIN="$BENCH/_build/http_server_nurl_h2"
RUST_BIN="$BENCH/rust_http2_server/target/release/http2_server"
JS_FILE="$BENCH/http2_server.js"

prep_nurl() {
    (( have_nurl )) || return 1
    local src="$BENCH/http_server.nu"
    local ll="$BENCH/_build/http_server_nurl_h2.ll"
    mkdir -p "$BENCH/_build"
    ( cd "$ROOT" && "$NURLC" "$src" > "$ll" ) || return 1
    local CURL_LIBS=""; [[ -f "$ROOT/stdlib/runtime.curl"    ]] && CURL_LIBS=$(pkg-config --libs libcurl 2>/dev/null)
    local SSL_LIBS="";  [[ -f "$ROOT/stdlib/runtime.openssl" ]] && SSL_LIBS=$(pkg-config --libs openssl 2>/dev/null)
    local SQ_LIBS="";   [[ -f "$ROOT/stdlib/runtime.sqlite3" ]] && SQ_LIBS=$(pkg-config --libs sqlite3 2>/dev/null)
    local PQ_LIBS="";   [[ -f "$ROOT/stdlib/runtime.pq"      ]] && PQ_LIBS=$(pkg-config --libs libpq 2>/dev/null)
    local Z_LIBS="";    [[ -f "$ROOT/stdlib/runtime.z"       ]] && Z_LIBS=$(pkg-config --libs zlib 2>/dev/null)
    local ZSTD_LIBS=""; [[ -f "$ROOT/stdlib/runtime.zstd"    ]] && ZSTD_LIBS=$(pkg-config --libs libzstd 2>/dev/null)
    clang -O2 -flto -Wl,--as-needed "$ll" "$RUNTIME" -lm -lpthread -ldl \
        $CURL_LIBS $SSL_LIBS $SQ_LIBS $PQ_LIBS $Z_LIBS $ZSTD_LIBS \
        -o "$NURL_BIN" 2>/dev/null
}
prep_rust() {
    (( have_rs )) || return 1
    cargo build --release --manifest-path "$BENCH/rust_http2_server/Cargo.toml" 2>/dev/null
}
prep_js() {
    (( have_js )) || return 1
    [[ -f "$JS_FILE" ]]
}

# run_server NAME SCHEME PORT H1REF -- CMD...
#   H1REF = 1 → also measure the HTTP/1.1 reference rows (NURL only).
# Emits ROW / H1 lines on stdout.
run_server() {
    local name="$1" scheme="$2" port="$3" h1ref="$4"
    shift 4
    [[ "$1" == "--" ]] && shift
    local cmd=("$@")
    "${cmd[@]}" > "$BENCH/_build/${name}-${scheme}-h2.stdout.log" 2> "$BENCH/_build/${name}-${scheme}-h2.stderr.log" &
    local pid=$!
    if ! wait_listen "$port"; then
        local cell
        for cell in $CELLS; do echo "ROW $scheme $name ${cell%x*} ${cell#*x} FAIL FAIL FAIL FAIL"; done
        stop_pid "$pid"
        return
    fi
    sleep "$(python3 -c "print($SETTLE_MS / 1000.0)")"
    local cell
    for cell in $CELLS; do
        local conns="${cell%x*}" streams="${cell#*x}"
        echo "ROW $scheme $name $conns $streams $(measure_cell h2 "$scheme" "$port" "$conns" "$streams")"
    done
    if (( h1ref )); then
        # HTTP/1.1 on the same server and listener, at every C that has a
        # P=1 cell — the protocol delta with everything else held equal.
        local seen=" "
        for cell in $CELLS; do
            local conns="${cell%x*}" streams="${cell#*x}"
            [[ "$streams" == 1 ]] || continue
            [[ "$seen" == *" $conns "* ]] && continue
            seen="$seen$conns "
            echo "H1 $scheme $conns $(measure_cell h1 "$scheme" "$port" "$conns" 1)"
        done
    fi
    stop_pid "$pid"
}

echo "# duration=${DURATION}s iters=${ITERS} cells=\"$CELLS\"" >&2

results=()
collect() { while read -r line; do results+=("$line"); done; }
na_rows() {
    local scheme="$1" name="$2" cell
    for cell in $CELLS; do results+=("ROW $scheme $name ${cell%x*} ${cell#*x} n/a n/a n/a n/a"); done
}

nurl_ready=0; prep_nurl && nurl_ready=1
rust_ready=0; prep_rust && rust_ready=1
js_ready=0;   prep_js   && js_ready=1

# Cleartext (h2c prior knowledge). Ports: NURL 18080 (its default), Rust
# 18091, Node 18092 — disjoint from run_http.sh's 18081/18082 peers.
if (( nurl_ready )); then collect < <(run_server nurl http 18080 1 -- "$NURL_BIN"); else na_rows http nurl; fi
if (( rust_ready )); then collect < <(run_server rust http 18091 0 -- "$RUST_BIN"); else na_rows http rust; fi
if (( js_ready ));   then collect < <(run_server node http 18092 0 -- node "$JS_FILE"); else na_rows http node; fi

# TLS (ALPN h2). Ports 18450-18452.
if (( have_tls )); then
    if (( nurl_ready )); then collect < <(run_server nurl https 18450 1 -- "$NURL_BIN" 18450 "$TLS_CERT" "$TLS_KEY"); else na_rows https nurl; fi
    if (( rust_ready )); then collect < <(run_server rust https 18451 0 -- env TLS_CERT="$TLS_CERT" TLS_KEY="$TLS_KEY" TLS_PORT=18451 "$RUST_BIN"); else na_rows https rust; fi
    if (( js_ready ));   then collect < <(run_server node https 18452 0 -- env TLS_CERT="$TLS_CERT" TLS_KEY="$TLS_KEY" TLS_PORT=18452 node "$JS_FILE"); else na_rows https node; fi
else
    na_rows https nurl; na_rows https rust; na_rows https node
fi

# ── report ──────────────────────────────────────────────────────────
{
    printf 'ENV\tnow\t%s\n' "$NOW"
    printf 'ENV\thost\t%s\n' "$HOST_LABEL"
    printf 'ENV\tkernel\t%s\n' "$HOST_KERNEL"
    printf 'ENV\tcpu\t%s\n' "$HOST_CPU"
    printf 'ENV\tcores\t%s\n' "$HOST_CORES"
    printf 'ENV\tmem_kb\t%s\n' "$HOST_MEM_KB"
    printf 'ENV\tcommit\t%s\n' "$COMMIT"
    printf 'ENV\trun_url\t%s\n' "$RUN_URL"
    printf 'ENV\tnurl\t%s\n' "$NURL_VERSION"
    printf 'ENV\trust\t%s\n' "$RUSTC_VERSION"
    printf 'ENV\tnode\t%s\n' "$NODE_VERSION"
    printf 'ENV\toha\t%s\n' "$OHA_VERSION"
    printf 'ENV\tduration\t%s\n' "$DURATION"
    printf 'ENV\titers\t%s\n' "$ITERS"
    printf 'ENV\tcells\t%s\n' "$CELLS"
    for row in "${results[@]}"; do
        printf '%s\n' "$row"
    done
} | python3 "$BENCH/gen_http2_results.py" > "$MD_OUT"
echo "wrote $MD_OUT" >&2
