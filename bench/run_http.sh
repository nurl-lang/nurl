#!/usr/bin/env bash
# bench/run_http.sh — HTTP + HTTPS peer-comparison benchmark.
#
# For each available HTTP-server implementation (NURL / Rust hyper /
# Node http), and for BOTH a plaintext HTTP and a TLS (HTTPS) listener,
# this script:
#   1. Builds / preps the server binary
#   2. Starts it on its dedicated loopback port (plaintext, then TLS)
#   3. Waits until the listener accepts (small TCP probe loop)
#   4. Runs `oha` for $DURATION seconds at concurrency $CONCURRENCY
#      with HTTP keep-alive enabled, against the server's URL (TLS runs
#      add `--insecure` so oha accepts the self-signed bench cert)
#   5. Kills the server
#   6. Captures requests/sec, p50 and p99 latency from oha's JSON
#
# It then OVERWRITES bench/HTTP_RESULTS.md with a fully generated report
# (environment + a plaintext table + a TLS table). That file is 100%
# generated — do not edit it by hand; the next run replaces it. This is
# the same contract bench/RESULTS.md has with bench/bench.sh.
#
# Usage:
#   bench/run_http.sh                        # defaults (see below)
#   DURATION=20 CONCURRENCY=200 bench/run_http.sh
#   bench/run_http.sh --concurrencies "1 10 100 200"
#   bench/run_http.sh --md /tmp/out.md       # write elsewhere
#
# Tools detected: nurlc (./build/), cargo (rust hyper), node, oha,
# openssl (for the self-signed TLS cert). Missing tools are reported
# "n/a" in the table.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH="$ROOT/bench"

DURATION="${DURATION:-10}"               # seconds per cell
CONCURRENCIES="${CONCURRENCIES:-1 10 50 200}"
SETTLE_MS="${SETTLE_MS:-500}"           # post-start spin-up before bench
WARMUP_SEC="${WARMUP_SEC:-2}"            # short pre-bench warmup load
KILL_WAIT="${KILL_WAIT:-1}"             # post-bench grace before SIGKILL
ITERS="${ITERS:-3}"                      # measurement runs per cell, median wins
MD_OUT="${MD_OUT:-$BENCH/HTTP_RESULTS.md}"

while (( $# > 0 )); do
    case "$1" in
        --concurrencies) CONCURRENCIES="$2"; shift 2 ;;
        --duration)      DURATION="$2"; shift 2 ;;
        --md)            MD_OUT="$2"; shift 2 ;;
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
OHA_VERSION="$($OHA --version 2>&1 | head -1)"
echo "# oha: $OHA_VERSION" >&2

have_nurl=0; [[ -x "$NURLC" && -f "$RUNTIME" ]] && have_nurl=1
have_rs=0;   command -v cargo >/dev/null && have_rs=1
have_js=0;   command -v node  >/dev/null && have_js=1
have_ssl=0;  command -v openssl >/dev/null && have_ssl=1

# ── TLS cert (self-signed, EC P-256, localhost) ─────────────────────
# One cert for all three TLS servers. EC because it exercises the ECDHE
# + ECDSA path a modern deployment negotiates (and the NURL facade takes
# an EC leaf directly). Regenerated each run so it never goes stale.
TLS_CERT="$BENCH/_build/tls-cert.pem"
TLS_KEY="$BENCH/_build/tls-key.pem"
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

# ── environment (mirrors bench.sh, for the generated report) ────────
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

# Run oha against <scheme>://127.0.0.1:<port>/ for $DURATION seconds at the
# given concurrency, then echo `<rps> <p50_ms> <p99_ms>`. `scheme` is http
# or https; an https run adds `--insecure` so oha accepts the self-signed
# bench cert. The JSON report is parsed via Python (already a build-dep of
# bench/gen_data.py, so a sibling reliance).
run_oha() {
    local scheme="$1"
    local port="$2"
    local concurrency="$3"
    local report="$BENCH/_build/oha-$scheme-$port-c$concurrency.json"
    local insecure=()
    [[ "$scheme" == https ]] && insecure=(--insecure)
    mkdir -p "$BENCH/_build"

    # Warmup: hit it briefly so JIT / OS-level caches settle (matters
    # most for Node; harmless on NURL / Rust). oha keeps connections
    # alive by default; we don't pass --disable-keepalive.
    "$OHA" --no-tui "${insecure[@]}" -n 1000 -c "$concurrency" \
        "$scheme://127.0.0.1:$port/" >/dev/null 2>&1 || true

    # Actual measurement. `-j` writes the report JSON to stdout, so
    # capture stdout into the file; stderr is muted (oha prints a
    # progress line that would otherwise contaminate the JSON).
    "$OHA" --no-tui "${insecure[@]}" -j -z "${DURATION}s" -c "$concurrency" \
        "$scheme://127.0.0.1:$port/" > "$report" 2>/dev/null \
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

median3() {   # median of the numbers on argv, printed with 2 decimals
    python3 -c "
import sys
vals=sorted(float(x) for x in sys.argv[1:])
m=vals[len(vals)//2] if len(vals)%2 else (vals[len(vals)//2-1]+vals[len(vals)//2])/2
print(f'{m:.2f}')" "$@"
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
    # nurlc resolves `$ "stdlib/..."` imports relative to its CWD —
    # must run from $ROOT so the stdlib tree is visible. Without
    # this, http_server.nu fails to parse with "cannot open
    # 'stdlib/ext/http_full.nu'". Same fix as compile_nurl in run.sh.
    ( cd "$ROOT" && "$NURLC" "$src" > "$ll" ) || return 1

    # Mirror compiler/tests/run_tests.sh's link line so optional FFI
    # libs resolve cleanly. `-ldl` is required because the TLS server
    # path reachable from this same binary pulls in the runtime's
    # dlopen references; without it the link fails with an undefined
    # `dlopen`/`dlsym` symbol.
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
    cargo build --release --manifest-path "$BENCH/rust_http_server/Cargo.toml" 2>/dev/null
}

prep_js() {
    (( have_js )) || return 1
    [[ -f "$JS_FILE" ]]
}

# ── one server, all concurrency cells ───────────────────────────────
# Args: <label> <scheme> <port> -- <command...>
# Env prefix for the command (e.g. TLS_CERT=...) is set by the caller.
run_server() {
    local name="$1"
    local scheme="$2"
    local port="$3"
    shift 3
    [[ "$1" == "--" ]] && shift
    local cmd=("$@")

    "${cmd[@]}" > "$BENCH/_build/${name}-${scheme}.stdout.log" 2> "$BENCH/_build/${name}-${scheme}.stderr.log" &
    local pid=$!
    if ! wait_listen "$port"; then
        for c in $CONCURRENCIES; do echo "$scheme $name $c FAIL FAIL FAIL"; done
        stop_pid "$pid"
        return
    fi

    # Brief settle window after listen accepts.
    sleep "$(python3 -c "print($SETTLE_MS / 1000.0)")"

    for c in $CONCURRENCIES; do
        # Run ITERS measurements at each cell, pick the median of rps.
        local rps_list=() p50_list=() p99_list=() i
        for i in $(seq 1 "$ITERS"); do
            local r rps p50 p99
            r=$(run_oha "$scheme" "$port" "$c")
            read -r rps p50 p99 <<<"$r"
            if [[ "$rps" == "FAIL" ]]; then
                echo "$scheme $name $c FAIL FAIL FAIL"
                rps_list=(); break
            fi
            rps_list+=("$rps"); p50_list+=("$p50"); p99_list+=("$p99")
        done
        (( ${#rps_list[@]} == 0 )) && continue
        local rps_med p50_med p99_med
        rps_med=$(python3 -c "
import sys
vals=sorted(float(x) for x in sys.argv[1:])
m=vals[len(vals)//2] if len(vals)%2 else (vals[len(vals)//2-1]+vals[len(vals)//2])/2
print(int(round(m)))" "${rps_list[@]}")
        p50_med=$(median3 "${p50_list[@]}")
        p99_med=$(median3 "${p99_list[@]}")
        echo "$scheme $name $c $rps_med $p50_med $p99_med"
    done

    stop_pid "$pid"
}

# ── run every (server × scheme) combination ─────────────────────────
# Plaintext ports 1808x; TLS ports 1844x. Collect flat result rows:
#   "<scheme> <name> <concurrency> <rps> <p50> <p99>"
echo "# duration=${DURATION}s iters=${ITERS} concurrencies=\"$CONCURRENCIES\"" >&2

results=()
collect() { while read -r line; do results+=("$line"); done; }
na_rows() { local scheme="$1" name="$2" c; for c in $CONCURRENCIES; do results+=("$scheme $name $c n/a n/a n/a"); done; }

nurl_ready=0; prep_nurl && nurl_ready=1
rust_ready=0; prep_rust && rust_ready=1
js_ready=0;   prep_js   && js_ready=1

# Plaintext HTTP (unchanged from the original single-mode benchmark).
if (( nurl_ready )); then collect < <(run_server nurl http 18080 -- "$NURL_BIN"); else na_rows http nurl; fi
if (( rust_ready )); then collect < <(run_server rust http 18081 -- "$RUST_BIN"); else na_rows http rust; fi
if (( js_ready ));   then collect < <(run_server node http 18082 -- node "$JS_FILE"); else na_rows http node; fi

# TLS HTTPS — the same servers, same load, over the self-signed EC cert.
if (( have_tls )); then
    # NURL takes cert/key as argv; Rust and Node read them from the
    # environment (`env VAR=val cmd` sets them for that server only).
    if (( nurl_ready )); then collect < <(run_server nurl https 18443 -- "$NURL_BIN" 18443 "$TLS_CERT" "$TLS_KEY"); else na_rows https nurl; fi
    if (( rust_ready )); then collect < <(run_server rust https 18444 -- env TLS_CERT="$TLS_CERT" TLS_KEY="$TLS_KEY" TLS_PORT=18444 "$RUST_BIN"); else na_rows https rust; fi
    if (( js_ready ));   then collect < <(run_server node https 18445 -- env TLS_CERT="$TLS_CERT" TLS_KEY="$TLS_KEY" TLS_PORT=18445 node "$JS_FILE"); else na_rows https node; fi
else
    na_rows https nurl; na_rows https rust; na_rows https node
fi

# ── generate the report ─────────────────────────────────────────────
# Everything the reader needs is passed to Python on stdin: the env
# block as `key=value` lines, a blank line, then one result row per line.
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
    printf 'ENV\tconcurrencies\t%s\n' "$CONCURRENCIES"
    for row in "${results[@]}"; do
        printf 'ROW\t%s\n' "$row"
    done
} | python3 "$BENCH/gen_http_results.py" > "$MD_OUT"

echo "wrote $MD_OUT" >&2
