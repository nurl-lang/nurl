#!/usr/bin/env bash
# bench/run_http.sh — HTTP peer-comparison benchmark.
#
# For each available HTTP-server implementation (NURL / Rust hyper /
# Node http), this script:
#   1. Builds / preps the server binary
#   2. Starts it on its dedicated loopback port
#   3. Waits until the listener accepts (small TCP probe loop)
#   4. Runs `oha` for $DURATION seconds at concurrency $CONCURRENCY
#      with HTTP keep-alive enabled, against http://127.0.0.1:<port>/
#   5. Kills the server
#   6. Captures requests/sec, p50 and p99 latency from oha's JSON
#
# Outputs a Markdown table on stdout; pipe into bench/HTTP_RESULTS.md
# to refresh the public numbers.
#
# Usage:
#   bench/run_http.sh                        # defaults (see below)
#   DURATION=20 CONCURRENCY=200 bench/run_http.sh
#   bench/run_http.sh --concurrencies "1 10 100 200"
#
# Tools detected: nurlc (./build/), cargo (rust hyper), node, oha.
# Missing tools are reported "n/a" in the table.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH="$ROOT/bench"

DURATION="${DURATION:-10}"               # seconds per cell
CONCURRENCIES="${CONCURRENCIES:-1 10 50 200}"
SETTLE_MS="${SETTLE_MS:-500}"           # post-start spin-up before bench
WARMUP_SEC="${WARMUP_SEC:-2}"            # short pre-bench warmup load
KILL_WAIT="${KILL_WAIT:-1}"             # post-bench grace before SIGKILL
ITERS="${ITERS:-3}"                      # measurement runs per cell, median wins

while (( $# > 0 )); do
    case "$1" in
        --concurrencies) CONCURRENCIES="$2"; shift 2 ;;
        --duration)      DURATION="$2"; shift 2 ;;
        *)               echo "unknown arg: $1" >&2; exit 2 ;;
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
echo "# oha: $($OHA --version 2>&1 | head -1)"

have_nurl=0; [[ -x "$NURLC" && -f "$RUNTIME" ]] && have_nurl=1
have_rs=0;   command -v cargo >/dev/null && have_rs=1
have_js=0;   command -v node  >/dev/null && have_js=1

# ── helpers ─────────────────────────────────────────────────────────
wait_listen() {
    # Poll the given port until something accepts. Caps at ~3 s.
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

# Run oha against http://127.0.0.1:<port>/ for $DURATION seconds at the
# given concurrency, then echo `<rps> <p50_ms> <p99_ms>`. Sends the
# JSON report to a temp file and parses it via Python (already a build-
# dep of bench/gen_data.py, so a sibling reliance).
run_oha() {
    local port="$1"
    local concurrency="$2"
    local report="$BENCH/_build/oha-$port-c$concurrency.json"
    mkdir -p "$BENCH/_build"

    # Warmup: hit it briefly so JIT / OS-level caches settle (matters
    # most for Node; harmless on NURL / Rust). oha keeps connections
    # alive by default; we don't pass --disable-keepalive.
    "$OHA" --no-tui -n 1000 -c "$concurrency" \
        "http://127.0.0.1:$port/" >/dev/null 2>&1 || true

    # Actual measurement. `-j` writes the report JSON to stdout, so
    # capture stdout into the file; stderr is muted (oha prints a
    # progress line that would otherwise contaminate the JSON).
    "$OHA" --no-tui -j -z "${DURATION}s" -c "$concurrency" \
        "http://127.0.0.1:$port/" > "$report" 2>/dev/null \
        || { echo "FAIL FAIL FAIL"; return; }

    python3 - "$report" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        r = json.load(f)
except Exception:
    print("FAIL FAIL FAIL")
    raise SystemExit
summary = r.get("summary", {})
if (summary.get("successRate", 0.0) or 0.0) < 0.99:
    print("FAIL FAIL FAIL")
    raise SystemExit
rps = summary.get("requestsPerSec", 0.0) or 0.0
lat = r.get("latencyPercentiles", {})
def ms(v):
    return (v * 1000.0) if isinstance(v, (int, float)) else 0.0
p50 = ms(lat.get("p50"))
p99 = ms(lat.get("p99"))
print(f"{rps:.0f} {p50:.2f} {p99:.2f}")
PY
}

# ── per-server preparation ──────────────────────────────────────────
NURL_BIN="$BENCH/_build/http_server_nurl"
RUST_BIN="$BENCH/rust_http_server/target/release/http_server"
JS_FILE="$BENCH/http_server.js"

prep_nurl() {
    (( have_nurl )) || return 1
    local src="$BENCH/http_server.nu"
    local ll="$BENCH/_build/http_server_nurl.ll"
    mkdir -p "$BENCH/_build"
    "$NURLC" "$src" > "$ll" || return 1

    # Mirror compiler/tests/run_tests.sh's link line so optional FFI
    # libs (libcurl + libssl needed by http_full.nu) resolve cleanly.
    local CURL_LIBS=""; [[ -f "$ROOT/stdlib/runtime.curl"    ]] && CURL_LIBS=$(pkg-config --libs libcurl 2>/dev/null)
    local SSL_LIBS="";  [[ -f "$ROOT/stdlib/runtime.openssl" ]] && SSL_LIBS=$(pkg-config --libs openssl 2>/dev/null)
    local SQ_LIBS="";   [[ -f "$ROOT/stdlib/runtime.sqlite3" ]] && SQ_LIBS=$(pkg-config --libs sqlite3 2>/dev/null)
    local PQ_LIBS="";   [[ -f "$ROOT/stdlib/runtime.pq"      ]] && PQ_LIBS=$(pkg-config --libs libpq 2>/dev/null)
    local Z_LIBS="";    [[ -f "$ROOT/stdlib/runtime.z"       ]] && Z_LIBS=$(pkg-config --libs zlib 2>/dev/null)
    local ZSTD_LIBS=""; [[ -f "$ROOT/stdlib/runtime.zstd"    ]] && ZSTD_LIBS=$(pkg-config --libs libzstd 2>/dev/null)

    clang -O2 -flto "$ll" "$RUNTIME" -lm -lpthread \
        $CURL_LIBS $SSL_LIBS $SQ_LIBS $PQ_LIBS $Z_LIBS $ZSTD_LIBS \
        -o "$NURL_BIN" 2>/dev/null
}

prep_rust() {
    (( have_rs )) || return 1
    cargo build --release --manifest-path "$BENCH/rust_http_server/Cargo.toml" 2>/dev/null
}

prep_js() {
    (( have_js )) || return 1
    [[ -f "$JS_FILE" ]]
}

# ── one server, all concurrency cells ───────────────────────────────
run_server() {
    local name="$1"
    local port="$2"
    shift 2
    local cmd=("$@")

    "${cmd[@]}" > "$BENCH/_build/${name}.stdout.log" 2> "$BENCH/_build/${name}.stderr.log" &
    local pid=$!
    if ! wait_listen "$port"; then
        echo "$name FAIL FAIL FAIL"
        stop_pid "$pid"
        return
    fi

    # Brief settle window after listen accepts.
    sleep "$(python3 -c "print($SETTLE_MS / 1000.0)")"

    for c in $CONCURRENCIES; do
        # Run ITERS measurements at each cell, pick the median of rps.
        local rps_list=()
        local p50_list=()
        local p99_list=()
        local i
        for i in $(seq 1 "$ITERS"); do
            local r rps p50 p99
            r=$(run_oha "$port" "$c")
            read -r rps p50 p99 <<<"$r"
            if [[ "$rps" == "FAIL" ]]; then
                echo "$name $c FAIL FAIL FAIL"
                stop_pid "$pid"
                return
            fi
            rps_list+=("$rps")
            p50_list+=("$p50")
            p99_list+=("$p99")
        done
        # Median of each. Use python so float sorts are correct.
        local med
        med=$(python3 -c "
import sys
vals=sorted(float(x) for x in sys.argv[1:])
m=vals[len(vals)//2] if len(vals)%2 else (vals[len(vals)//2-1]+vals[len(vals)//2])/2
print(f'{int(round(m))} {m:.2f}')" "${rps_list[@]}")
        local rps_med=$(echo "$med" | awk '{print $1}')
        local p50_med=$(python3 -c "
import sys
vals=sorted(float(x) for x in sys.argv[1:])
m=vals[len(vals)//2] if len(vals)%2 else (vals[len(vals)//2-1]+vals[len(vals)//2])/2
print(f'{m:.2f}')" "${p50_list[@]}")
        local p99_med=$(python3 -c "
import sys
vals=sorted(float(x) for x in sys.argv[1:])
m=vals[len(vals)//2] if len(vals)%2 else (vals[len(vals)//2-1]+vals[len(vals)//2])/2
print(f'{m:.2f}')" "${p99_list[@]}")
        echo "$name $c $rps_med $p50_med $p99_med"
    done

    stop_pid "$pid"
}

# ── main ────────────────────────────────────────────────────────────
echo "# duration=${DURATION}s concurrencies=\"$CONCURRENCIES\""

results=()

if prep_nurl; then
    while read -r line; do
        results+=("$line")
    done < <(run_server nurl 18080 "$NURL_BIN")
else
    for c in $CONCURRENCIES; do results+=("nurl $c n/a n/a n/a"); done
fi

if prep_rust; then
    while read -r line; do
        results+=("$line")
    done < <(run_server rust 18081 "$RUST_BIN")
else
    for c in $CONCURRENCIES; do results+=("rust $c n/a n/a n/a"); done
fi

if prep_js; then
    while read -r line; do
        results+=("$line")
    done < <(run_server node 18082 node "$JS_FILE")
else
    for c in $CONCURRENCIES; do results+=("node $c n/a n/a n/a"); done
fi

# ── format as Markdown table ────────────────────────────────────────
echo
echo "| Server | Concurrency |    req/s | p50 (ms) | p99 (ms) |"
echo "|--------|------------:|---------:|---------:|---------:|"
for row in "${results[@]}"; do
    read -r name c rps p50 p99 <<<"$row"
    printf '| %-6s | %11s | %8s | %8s | %8s |\n' "$name" "$c" "$rps" "$p50" "$p99"
done
