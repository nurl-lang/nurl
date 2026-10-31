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
#   bench/run_http.sh --suite db             # the database suite (below)
#
# `--suite db` measures the database-backed endpoints instead — the
# TechEmpower tests (/json /db /queries /fortunes /updates) and HttpArena's
# async-db profile — NURL against Rust (hyper + tokio-postgres; Node has no
# database peer here), with the same lock, pinning and CPU-per-request
# method, and writes bench/HTTP_DB_RESULTS.md. The database is the one
# $DATABASE_URL names (schema: bench/http_db_schema.sql, loaded by hand
# there — the harness never drops tables it did not create), or, without
# it, a throwaway cluster the harness starts with the PostgreSQL server
# binaries it finds (initdb / pg_ctl on PATH or under
# /usr/lib/postgresql/*/bin), loads, pins to cores of its own and removes
# afterwards. DB_PATHS and DB_CONCURRENCIES shape the cells.
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
HS_REQS="${HS_REQS:-20000}"             # connections for the setup-rate cell
HS_CONC="${HS_CONC:-20}"                # its concurrency (kept low to bound TIME_WAIT)
MD_OUT="${MD_OUT:-}"
SUITE="${SUITE:-plain}"                  # plain (HTTP + TLS) | db
DB_PATHS="${DB_PATHS:-/json /db /queries?queries=20 /fortunes /updates?queries=20 /async-db?limit=50}"
DB_CONCURRENCIES="${DB_CONCURRENCIES:-64 256}"

while (( $# > 0 )); do
    case "$1" in
        --concurrencies) CONCURRENCIES="$2"; shift 2 ;;
        --duration)      DURATION="$2"; shift 2 ;;
        --md)            MD_OUT="$2"; shift 2 ;;
        --suite)         SUITE="$2"; shift 2 ;;
        *)               echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done
case "$SUITE" in
    plain) [[ -n "$MD_OUT" ]] || MD_OUT="$BENCH/HTTP_RESULTS.md" ;;
    db)    [[ -n "$MD_OUT" ]] || MD_OUT="$BENCH/HTTP_DB_RESULTS.md" ;;
    *)     echo "unknown suite: $SUITE (plain | db)" >&2; exit 2 ;;
esac

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
# The JSON report: `-j` up to oha 1.x's early releases (CI pins 1.8.0),
# `--output-format json` once `-j` was dropped.
if "$OHA" --help 2>&1 | grep -q -- '--output-format'; then OHA_JSON=(--output-format json); else OHA_JSON=(-j); fi

have_nurl=0; [[ -x "$NURLC" && -f "$RUNTIME" ]] && have_nurl=1
have_rs=0;   command -v cargo >/dev/null && have_rs=1
have_js=0;   command -v node  >/dev/null && have_js=1
have_ssl=0;  command -v openssl >/dev/null && have_ssl=1

# ── core isolation + worker equalisation ────────────────────────────
# Planned rigor #2: the load generator must not compete with the server
# for CPU. Without this every cell measures the pair, not the server —
# on a 12-core box the default per-core worker count sits PAST the
# throughput peak once oha's threads are in the way, and CPU/request
# rises with worker count for every runtime, so an unpinned table can
# manufacture a large peer "gap" out of nothing but concurrency.
#
# The server gets the low half of the cores, oha the high half. Both
# halves are also the worker count handed to the runtimes that take one
# (NURL and tokio), so the peers are compared at equal parallelism.
# Node's http server is single-threaded and is reported as such.
HOST_NPROC="$(nproc 2>/dev/null || echo 1)"

# ── one measurement at a time, per machine ──────────────────────────
# Pinning makes the harness pick a fixed set of cores, which means two
# runs on one box do not merely slow each other down: they land on the
# SAME cores and silently corrupt each other. Observed, not theorised —
# two agents benchmarking the same repo from two checkouts produced one
# cell at 36.81 us/req against a true 24.09, and the only clue was that
# the number was absurd. An etiquette rule ("say before you measure")
# does not survive the first forgotten message, so take a machine-wide
# advisory lock instead and let the second run WAIT rather than publish
# a poisoned number. BENCH_NO_LOCK=1 opts out for a deliberately
# concurrent experiment.
BENCH_LOCK="${BENCH_LOCK:-${TMPDIR:-/tmp}/nurl-bench-http.lock}"
BENCH_LOCK_WAIT="${BENCH_LOCK_WAIT:-3600}"
if [[ "${BENCH_NO_LOCK:-0}" != 1 ]] && command -v flock >/dev/null; then
    exec 9>"$BENCH_LOCK" || true
    if ! flock -n 9 2>/dev/null; then
        echo "# another bench run holds $BENCH_LOCK — waiting up to ${BENCH_LOCK_WAIT}s" >&2
        if ! flock -w "$BENCH_LOCK_WAIT" 9 2>/dev/null; then
            echo "ERROR: timed out waiting for $BENCH_LOCK; refusing to measure into a contended machine" >&2
            exit 3
        fi
    fi
fi

# ── and not into a loaded machine ───────────────────────────────────
# The lock above stops two BENCHMARKS from colliding. It does nothing
# about the compiler test suite running with six jobs in the checkout
# next door, which loads every core and inflates every cell just as
# effectively. Wait for the machine to go quiet; if it will not, measure
# anyway (CI must not hang) but record the load in the report, so the
# number can never be read as if it had been taken on an idle box.
BENCH_LOAD_WAIT="${BENCH_LOAD_WAIT:-300}"
# Half the cores busy is already enough to move us/req; below that the
# pinning absorbs it.
BENCH_MAX_LOAD="${BENCH_MAX_LOAD:-$(python3 -c "print(max(1.0, $HOST_NPROC / 2.0))")}"
load_now() { awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0; }
LOAD_AT_START="$(load_now)"
if [[ "${BENCH_NO_LOADCHECK:-0}" != 1 ]]; then
    _waited=0
    while python3 -c "import sys; sys.exit(0 if $(load_now) > $BENCH_MAX_LOAD else 1)" 2>/dev/null; do
        if (( _waited == 0 )); then
            echo "# load $(load_now) > $BENCH_MAX_LOAD — waiting up to ${BENCH_LOAD_WAIT}s for the machine to go quiet" >&2
        fi
        (( _waited >= BENCH_LOAD_WAIT )) && break
        sleep 10; _waited=$(( _waited + 10 ))
    done
    LOAD_AT_START="$(load_now)"
    if python3 -c "import sys; sys.exit(0 if $LOAD_AT_START > $BENCH_MAX_LOAD else 1)" 2>/dev/null; then
        echo "WARNING: measuring at load $LOAD_AT_START (threshold $BENCH_MAX_LOAD) — the report will say so" >&2
    fi
fi

PIN=0
SRV_CORES="${SRV_CORES:-}"
GEN_CORES="${GEN_CORES:-}"
DB_CORES="${DB_CORES:-}"
if command -v taskset >/dev/null && (( HOST_NPROC >= 4 )); then
    half=$(( HOST_NPROC / 2 ))
    [[ -z "$SRV_CORES" ]] && SRV_CORES="0-$((half - 1))"
    if [[ "$SUITE" == db ]]; then
        # The database is a third process on the critical path: it gets a
        # quarter of the cores (at least one) out of the generator's half,
        # so neither the server nor oha shares a core with it.
        quarter=$(( HOST_NPROC / 4 )); (( quarter < 1 )) && quarter=1
        [[ -z "$DB_CORES" ]] && DB_CORES="$half-$((half + quarter - 1))"
        [[ -z "$GEN_CORES" ]] && GEN_CORES="$((half + quarter))-$((HOST_NPROC - 1))"
    else
        [[ -z "$GEN_CORES" ]] && GEN_CORES="$half-$((HOST_NPROC - 1))"
    fi
    PIN=1
fi
SRV_WORKERS="${SRV_WORKERS:-}"
if [[ -z "$SRV_WORKERS" ]]; then
    if (( PIN )); then SRV_WORKERS=$(( HOST_NPROC / 2 )); else SRV_WORKERS="$HOST_NPROC"; fi
fi
# Applied to the server command; empty when unpinned.
srv_pin=(); (( PIN )) && srv_pin=(taskset -c "$SRV_CORES")
gen_pin=(); (( PIN )) && gen_pin=(taskset -c "$GEN_CORES")
# Equal parallelism for the runtimes that size a pool from nproc.
srv_env=(env "NURL_WORKERS=$SRV_WORKERS" "TOKIO_WORKER_THREADS=$SRV_WORKERS")
if (( PIN )); then
    echo "# pinned: server cores $SRV_CORES, generator cores $GEN_CORES, $SRV_WORKERS workers" >&2
else
    echo "# NOT pinned (taskset missing or < 4 cores): server and generator share $HOST_NPROC cores" >&2
fi

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

# Parse an oha JSON report into `<rps> <p50_ms> <p99_ms> <mean_ms>`, or
# `FAIL FAIL FAIL FAIL` on a failed run. The mean latency is what the
# effective-concurrency check (Little's law, N ≈ rps × mean) uses to flag
# a closed-loop cell whose latency reflects fewer connections than were
# offered — see gen_http_results.py.
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
# Exact number of responses, from the status-code histogram. The
# CPU-per-request figure divides by THIS, never by rps*duration:
# that approximation is several percent off, which is the size of
# the very differences the comparison exists to resolve.
codes = r.get("statusCodeDistribution", {}) or {}
reqs = sum(codes.values()) if codes else 0
print(f"{rps:.0f} {ms(lat.get('p50')):.2f} {ms(lat.get('p99')):.2f} {mean*1000.0:.4f} {reqs}")
PY
}

# Closed-loop throughput/latency cell. Runs oha against
# <scheme>://127.0.0.1:<port>/ for $DURATION seconds at the given
# concurrency, keep-alive on, and echoes `<rps> <p50> <p99> <mean_ms>`.
# `scheme` https adds `--insecure` so oha accepts the self-signed cert.
# Server CPU so far, in clock ticks: utime+stime from /proc/<pid>/stat
# (fields 14 and 15), which for a thread-group leader are the totals
# across every thread of the process. Read externally, so it needs no
# getrusage call inside any peer and works identically for NURL, Rust
# and Node.
cpu_ticks() {
    local pid="$1"
    awk '{print $14 + $15}' "/proc/$pid/stat" 2>/dev/null || echo ""
}

run_oha() {
    local scheme="$1" port="$2" concurrency="$3" pid="${4:-}" path="${5:-/}"
    local tag; tag="$(printf '%s' "$path" | tr -c 'A-Za-z0-9' '_')"
    local report="$BENCH/_build/oha-$scheme-$port-c$concurrency$tag.json"
    local insecure=(); [[ "$scheme" == https ]] && insecure=(--insecure)
    mkdir -p "$BENCH/_build"

    # Warmup: hit it briefly so JIT / OS-level caches settle (matters
    # most for Node; harmless on NURL / Rust). oha keeps connections
    # alive by default; we don't pass --disable-keepalive. Deliberately
    # OUTSIDE the CPU window below — warmup CPU is not per-request cost.
    "${gen_pin[@]}" "$OHA" --no-tui "${insecure[@]}" -n 1000 -c "$concurrency" \
        "$scheme://127.0.0.1:$port$path" >/dev/null 2>&1 || true

    local t0 t1; t0="$(cpu_ticks "$pid")"
    "${gen_pin[@]}" "$OHA" --no-tui "${insecure[@]}" "${OHA_JSON[@]}" -z "${DURATION}s" -c "$concurrency" \
        "$scheme://127.0.0.1:$port$path" > "$report" 2>/dev/null \
        || { echo "FAIL FAIL FAIL FAIL FAIL FAIL"; return; }
    t1="$(cpu_ticks "$pid")"

    local parsed; parsed="$(_parse_oha "$report")"
    # Append the CPU ticks consumed during the measured window; the
    # caller turns (ticks, requests) into us/request once per cell.
    local ticks=""
    [[ -n "$t0" && -n "$t1" ]] && ticks=$(( t1 - t0 ))
    echo "$parsed ${ticks:-FAIL}"
}

# Connection-setup-rate cell. `--disable-keepalive` opens a fresh
# connection per request, so oha's rps here IS connections/second — and
# for an https run, TLS handshakes/second: the pure-NURL P-256 ECDHE +
# ECDSA-verify cost against rustls, the one number a short-lived-
# connection edge deployment actually pays and that the keep-alive tables
# amortise away. Bounded by a fixed request count (not duration) so the
# fast plaintext case cannot flood the loopback with TIME_WAIT sockets.
# Echoes `<conn_per_s>` or `FAIL`.
run_oha_conn() {
    local scheme="$1" port="$2"
    local report="$BENCH/_build/ohaconn-$scheme-$port.json"
    local insecure=(); [[ "$scheme" == https ]] && insecure=(--insecure)
    "${gen_pin[@]}" "$OHA" --no-tui "${insecure[@]}" --disable-keepalive "${OHA_JSON[@]}" -n "$HS_REQS" -c "$HS_CONC" \
        "$scheme://127.0.0.1:$port/" > "$report" 2>/dev/null \
        || { echo "FAIL"; return; }
    _parse_oha "$report" | awk '{print $1}'
}

median3() {   # median of the numbers on argv, printed with 2 decimals
    python3 -c "
import sys
vals=sorted(float(x) for x in sys.argv[1:])
m=vals[len(vals)//2] if len(vals)%2 else (vals[len(vals)//2-1]+vals[len(vals)//2])/2
print(f'{m:.2f}')" "$@"
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

# ── one cell: ITERS runs of one (server, path, concurrency) ─────────
# Echoes `<rps> <p50> <p99> <mean_ms> <us_req>` — the median of rps (and
# of each latency) over ITERS runs — or five FAILs. CPU per request is NOT
# a median: ticks and requests are summed over every iteration and
# divided once, so the figure is the true cost over the whole measured
# window.
measure_cell() {
    local scheme="$1" port="$2" c="$3" pid="$4" path="${5:-/}"
    local rps_list=() p50_list=() p99_list=() mean_list=() i
    local ticks_sum=0 reqs_sum=0 cpu_ok=1
    for i in $(seq 1 "$ITERS"); do
        local r rps p50 p99 mean reqs ticks
        r=$(run_oha "$scheme" "$port" "$c" "$pid" "$path")
        read -r rps p50 p99 mean reqs ticks <<<"$r"
        if [[ "$rps" == "FAIL" ]]; then
            echo "FAIL FAIL FAIL FAIL FAIL"
            return
        fi
        rps_list+=("$rps"); p50_list+=("$p50"); p99_list+=("$p99"); mean_list+=("$mean")
        if [[ "$ticks" == "FAIL" || "$reqs" == "0" || -z "$reqs" ]]; then
            cpu_ok=0
        else
            ticks_sum=$(( ticks_sum + ticks )); reqs_sum=$(( reqs_sum + reqs ))
        fi
    done
    local rps_med p50_med p99_med mean_med
    rps_med=$(python3 -c "
import sys
vals=sorted(float(x) for x in sys.argv[1:])
m=vals[len(vals)//2] if len(vals)%2 else (vals[len(vals)//2-1]+vals[len(vals)//2])/2
print(int(round(m)))" "${rps_list[@]}")
    p50_med=$(median3 "${p50_list[@]}")
    p99_med=$(median3 "${p99_list[@]}")
    mean_med=$(median3 "${mean_list[@]}")
    local us_req="n/a"
    if (( cpu_ok )) && (( reqs_sum > 0 )); then
        us_req=$(python3 -c "
import os
hz = os.sysconf('SC_CLK_TCK')
print('%.2f' % ($ticks_sum / hz / $reqs_sum * 1e6))")
    fi
    echo "$rps_med $p50_med $p99_med $mean_med $us_req"
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

    # Pinned to the server half of the cores, with the worker pool of
    # every runtime that takes one set to the same number, so the peers
    # are compared at equal parallelism on cores oha cannot touch.
    "${srv_pin[@]}" "${srv_env[@]}" "${cmd[@]}" > "$BENCH/_build/${name}-${scheme}.stdout.log" 2> "$BENCH/_build/${name}-${scheme}.stderr.log" &
    local pid=$!
    # Kill the server however this function leaves — a Ctrl-C or a
    # timeout partway through a cell used to leak it, and the leaked
    # server then held the port for the NEXT run, which is the failure
    # the startup guard below catches. Catch it at the source too. The
    # trap belongs here, not at the top level: run_server is called
    # inside a process substitution, and a subshell does not inherit
    # the parent's traps.
    trap 'kill -TERM '"$pid"' 2>/dev/null; exit' INT TERM
    trap 'kill -TERM '"$pid"' 2>/dev/null' EXIT
    # wait_listen only proves SOMETHING accepts on that port — it cannot
    # tell our server from a stale one left behind by an earlier run. A
    # benchmark that silently measures a foreign process is worse than
    # one that fails, so check our own child is still alive and treat a
    # dead child on a live port as the port conflict it is.
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "ERROR: $name $scheme died at startup — port $port already in use?" >&2
        sed -n '1,3p' "$BENCH/_build/${name}-${scheme}.stderr.log" >&2 2>/dev/null
        local c
        for c in $CONCURRENCIES; do echo "ROW $scheme $name $c FAIL FAIL FAIL FAIL FAIL"; done
        echo "HS $scheme $name FAIL"
        return
    fi
    if ! wait_listen "$port"; then
        local c
        for c in $CONCURRENCIES; do echo "ROW $scheme $name $c FAIL FAIL FAIL FAIL FAIL"; done
        echo "HS $scheme $name FAIL"
        stop_pid "$pid"
        return
    fi

    # Brief settle window after listen accepts.
    sleep "$(python3 -c "print($SETTLE_MS / 1000.0)")"
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "ERROR: $name $scheme exited during startup; the port was answered by another process" >&2
        sed -n '1,3p' "$BENCH/_build/${name}-${scheme}.stderr.log" >&2 2>/dev/null
        local c
        for c in $CONCURRENCIES; do echo "ROW $scheme $name $c FAIL FAIL FAIL FAIL FAIL"; done
        echo "HS $scheme $name FAIL"
        return
    fi

    for c in $CONCURRENCIES; do
        echo "ROW $scheme $name $c $(measure_cell "$scheme" "$port" "$c" "$pid" /)"
    done

    # Connection-setup rate (one bounded run, this server still up): plain
    # conn/s for http, TLS handshakes/s for https.
    local conn
    conn=$(run_oha_conn "$scheme" "$port")
    echo "HS $scheme $name $conn"

    stop_pid "$pid"
}

# ── the db suite ────────────────────────────────────────────────────
# Its own run and its own report: the endpoints a framework deploys over a
# database (TechEmpower's five, HttpArena's async-db), NURL vs Rust. Every
# endpoint is checked on both servers before a single request is timed —
# a peer that answers the wrong thing fast is not measured.
if [[ "$SUITE" == db ]]; then
    db_cluster=""
    DB_PLACEMENT="\$DATABASE_URL (not placed by the harness)"
    as_pg() {
        if [ "$(id -u)" = 0 ]; then setpriv --reuid="${BENCH_PG_USER:-postgres}" --regid="${BENCH_PG_USER:-postgres}" --init-groups "$@"
        else "$@"; fi
    }
    db_stop() {
        if [[ -n "$db_cluster" ]]; then
            as_pg "$PG_BIN/pg_ctl" -D "$db_cluster/data" -m immediate stop >/dev/null 2>&1 || true
            rm -rf "$db_cluster"
        fi
    }
    trap db_stop EXIT
    PG_BIN="$(dirname "$(command -v initdb 2>/dev/null || ls -d /usr/lib/postgresql/*/bin/initdb 2>/dev/null | sort -V | tail -1)")"
    PSQL_CLI="$PG_BIN/psql"; [[ -x "$PSQL_CLI" ]] || PSQL_CLI="$(command -v psql 2>/dev/null || true)"
    if [[ -z "${DATABASE_URL:-}" ]]; then
        if [[ ! -x "$PG_BIN/initdb" || -z "$PSQL_CLI" ]]; then
            echo "ERROR: --suite db needs DATABASE_URL, or the PostgreSQL server binaries (initdb, pg_ctl, psql) to start its own" >&2
            exit 2
        fi
        DB_PORT="${DB_PORT:-55444}"
        db_cluster="$(mktemp -d /tmp/nurl-bench-pg.XXXXXX)"
        chmod 755 "$db_cluster"
        [ "$(id -u)" = 0 ] && chown "${BENCH_PG_USER:-postgres}" "$db_cluster"
        echo bench > "$db_cluster/pw"; chmod 644 "$db_cluster/pw"
        as_pg "$PG_BIN/initdb" -D "$db_cluster/data" -U bench --pwfile="$db_cluster/pw" \
            --auth=scram-sha-256 -E UTF8 >/dev/null || { echo "ERROR: initdb failed" >&2; exit 2; }
        # Durability off: the comparison is the frameworks', not the disk's
        # (a throwaway cluster; /updates would otherwise time fsyncs).
        as_pg sh -c "printf '%s\n' \"port = $DB_PORT\" \"listen_addresses = '127.0.0.1'\" \"unix_socket_directories = '$db_cluster'\" 'fsync = off' 'synchronous_commit = off' 'full_page_writes = off' >> '$db_cluster/data/postgresql.conf'"
        db_pin=(); (( PIN )) && db_pin=(taskset -c "$DB_CORES")
        "${db_pin[@]}" bash -c "$(declare -f as_pg); as_pg '$PG_BIN/pg_ctl' -D '$db_cluster/data' -l '$db_cluster/log' -w start" >/dev/null \
            || { echo "ERROR: pg_ctl start failed" >&2; sed -n '1,20p' "$db_cluster/log" >&2; exit 2; }
        export DATABASE_URL="postgres://bench:bench@127.0.0.1:$DB_PORT/postgres?sslmode=disable"
        "$PSQL_CLI" "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$BENCH/http_db_schema.sql" >/dev/null 2>&1 \
            || { echo "ERROR: loading bench/http_db_schema.sql failed" >&2; exit 2; }
        DB_VERSION="$("$PSQL_CLI" "$DATABASE_URL" -tAc 'SHOW server_version' 2>/dev/null)"
        if (( PIN )); then DB_PLACEMENT="throwaway PostgreSQL $DB_VERSION on cores \`$DB_CORES\` (\`taskset\`), durability off"
        else DB_PLACEMENT="throwaway PostgreSQL $DB_VERSION, unpinned, durability off"; fi
    fi
    echo "# db: $DB_PLACEMENT" >&2

    # The endpoint contract, checked on a live server: `db_check port`
    # prints `ok` or the first broken check.
    db_check() {
        python3 - "$1" <<'PY'
import json, sys, urllib.request
base = f"http://127.0.0.1:{sys.argv[1]}"
def get(path):
    with urllib.request.urlopen(base + path, timeout=10) as r:
        return r.status, r.headers.get("Content-Type", ""), r.read()
def world(o):
    return isinstance(o, dict) and set(o) == {"id", "randomNumber"} and 1 <= o["id"] <= 10000 and isinstance(o["randomNumber"], int)
def check():
    s, ct, b = get("/json")
    if s != 200 or "application/json" not in ct or json.loads(b) != {"message": "Hello, World!"}: return "/json"
    s, ct, b = get("/db")
    if s != 200 or "application/json" not in ct or not world(json.loads(b)): return "/db"
    for q, n in (("20", 20), ("0", 1), ("foo", 1), ("501", 500)):
        s, ct, b = get("/queries?queries=" + q)
        v = json.loads(b)
        if s != 200 or not isinstance(v, list) or len(v) != n or not all(map(world, v)): return "/queries?queries=" + q
    s, ct, b = get("/fortunes")
    h = b.decode("utf-8")
    if s != 200 or "text/html" not in ct or h.count("<tr>") != 14: return "/fortunes rows"
    if "<td>11</td><td>&lt;script&gt;alert(&quot;This should not be displayed in a browser alert box.&quot;);&lt;/script&gt;</td>" not in h: return "/fortunes escaping"
    if "<td>0</td><td>Additional fortune added at request time.</td>" not in h or "フレームワークのベンチマーク" not in h: return "/fortunes content"
    rows = [r.split("</td><td>")[1].split("</td>")[0] for r in h.split("<tr>")[2:]]
    if rows != sorted(rows, key=lambda t: t.encode("utf-8")): return "/fortunes order"
    s, ct, b = get("/updates?queries=5")
    v = json.loads(b)
    if s != 200 or not isinstance(v, list) or len(v) != 5 or not all(map(world, v)): return "/updates"
    s, ct, b = get("/async-db?min=10&max=50&limit=5")
    v = json.loads(b)
    if s != 200 or "application/json" not in ct or v.get("count") != 5 or len(v.get("items", [])) != 5: return "/async-db"
    for it in v["items"]:
        if not (10 <= it["price"] <= 50 and isinstance(it["tags"], list) and set(it["rating"]) == {"score", "count"}): return "/async-db item"
    return "ok"
try:
    print(check())
except Exception as e:
    print(f"error: {e}")
PY
    }

    # Both servers run at once, pinned to the same cores — an idle one
    # costs nothing — and their cells alternate (NURL's, then Rust's, for
    # each path and concurrency): a noisy minute on a shared VM then lands
    # on both peers instead of on whichever was being measured.
    # Args: <name> <port> -- <command...>; prints the pid. The server reads
    # DATABASE_URL.
    start_db_server() {
        local name="$1" port="$2"; shift 2
        [[ "$1" == "--" ]] && shift
        "${srv_pin[@]}" "${srv_env[@]}" "DATABASE_URL=$DATABASE_URL" "$@" \
            > "$BENCH/_build/${name}-db.stdout.log" 2> "$BENCH/_build/${name}-db.stderr.log" &
        echo $!
    }
    # `ok`, or why this server will not be measured.
    db_ready() {
        local pid="$1" port="$2"
        if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null || ! wait_listen "$port"; then
            echo "did not start"; return
        fi
        sleep "$(python3 -c "print($SETTLE_MS / 1000.0)")"
        kill -0 "$pid" 2>/dev/null || { echo "exited at startup (port $port in use?)"; return; }
        db_check "$port"
    }

    echo "# db suite: duration=${DURATION}s iters=${ITERS} paths=\"$DB_PATHS\" concurrencies=\"$DB_CONCURRENCIES\"" >&2
    results=()
    declare -A db_pid=() db_port=([nurl]=18080 [rust]=18081) db_verdict=()
    prep_nurl && db_pid[nurl]="$(start_db_server nurl 18080 -- "$NURL_BIN")"
    prep_rust && db_pid[rust]="$(start_db_server rust 18081 -- "$RUST_BIN")"
    trap 'for p in "${db_pid[@]}"; do kill -TERM "$p" 2>/dev/null; done; db_stop' EXIT
    trap 'exit 130' INT TERM
    for name in nurl rust; do
        if [[ -n "${db_pid[$name]:-}" ]]; then db_verdict[$name]="$(db_ready "${db_pid[$name]}" "${db_port[$name]}")"
        else db_verdict[$name]="n/a"; fi
        results+=("DBCHECK $name ${db_verdict[$name]}")
    done
    steal0="$(awk '/^cpu /{print $9; exit}' /proc/stat)"; total0="$(awk '/^cpu /{s=0; for(i=2;i<=NF;i++) s+=$i; print s; exit}' /proc/stat)"
    for path in $DB_PATHS; do
        for c in $DB_CONCURRENCIES; do
            for name in nurl rust; do
                case "${db_verdict[$name]}" in
                    ok)  results+=("DBROW $path $name $c $(measure_cell http "${db_port[$name]}" "$c" "${db_pid[$name]}" "$path")") ;;
                    n/a) results+=("DBROW $path $name $c n/a n/a n/a n/a n/a") ;;
                    *)   results+=("DBROW $path $name $c FAIL FAIL FAIL FAIL FAIL") ;;
                esac
            done
        done
    done
    steal1="$(awk '/^cpu /{print $9; exit}' /proc/stat)"; total1="$(awk '/^cpu /{s=0; for(i=2;i<=NF;i++) s+=$i; print s; exit}' /proc/stat)"
    DB_STEAL="$(python3 -c "print('%.2f' % (100.0 * ($steal1 - $steal0) / max(1, $total1 - $total0)))")"
    for name in nurl rust; do [[ -n "${db_pid[$name]:-}" ]] && stop_pid "${db_pid[$name]}"; done

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
        printf 'ENV\toha\t%s\n' "$OHA_VERSION"
        printf 'ENV\tduration\t%s\n' "$DURATION"
        printf 'ENV\titers\t%s\n' "$ITERS"
        printf 'ENV\tpaths\t%s\n' "$DB_PATHS"
        printf 'ENV\tconcurrencies\t%s\n' "$DB_CONCURRENCIES"
        printf 'ENV\tpinned\t%s\n' "$( (( PIN )) && echo yes || echo no )"
        printf 'ENV\tsrv_cores\t%s\n' "${SRV_CORES:-n/a}"
        printf 'ENV\tgen_cores\t%s\n' "${GEN_CORES:-n/a}"
        printf 'ENV\tdb\t%s\n' "$DB_PLACEMENT"
        printf 'ENV\tsteal\t%s\n' "$DB_STEAL"
        printf 'ENV\tworkers\t%s\n' "$SRV_WORKERS"
        printf 'ENV\tload\t%s\n' "$LOAD_AT_START"
        printf 'ENV\tmax_load\t%s\n' "$BENCH_MAX_LOAD"
        for row in "${results[@]}"; do printf '%s\n' "$row"; done
    } | python3 "$BENCH/gen_http_db_results.py" > "$MD_OUT"
    echo "wrote $MD_OUT" >&2
    exit 0
fi

# ── run every (server × scheme) combination ─────────────────────────
# Plaintext ports 1808x; TLS ports 1844x. run_server emits its own
# tokenised lines (`ROW scheme name c rps p50 p99 mean` and
# `HS scheme name conn_per_s`), collected verbatim.
echo "# duration=${DURATION}s iters=${ITERS} concurrencies=\"$CONCURRENCIES\"" >&2

results=()
collect() { while read -r line; do results+=("$line"); done; }
na_rows() {
    local scheme="$1" name="$2" c
    for c in $CONCURRENCIES; do results+=("ROW $scheme $name $c n/a n/a n/a n/a n/a"); done
    results+=("HS $scheme $name n/a")
}

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
    printf 'ENV\ths_reqs\t%s\n' "$HS_REQS"
    printf 'ENV\ths_conc\t%s\n' "$HS_CONC"
    printf 'ENV\tpinned\t%s\n' "$( (( PIN )) && echo yes || echo no )"
    printf 'ENV\tsrv_cores\t%s\n' "${SRV_CORES:-n/a}"
    printf 'ENV\tgen_cores\t%s\n' "${GEN_CORES:-n/a}"
    printf 'ENV\tworkers\t%s\n' "$SRV_WORKERS"
    printf 'ENV\tload\t%s\n' "$LOAD_AT_START"
    printf 'ENV\tmax_load\t%s\n' "$BENCH_MAX_LOAD"
    # run_server / na_rows lines already carry their ROW / HS tag.
    for row in "${results[@]}"; do
        printf '%s\n' "$row"
    done
} | python3 "$BENCH/gen_http_results.py" > "$MD_OUT"

echo "wrote $MD_OUT" >&2
