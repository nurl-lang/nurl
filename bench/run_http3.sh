#!/usr/bin/env bash
# bench/run_http3.sh — HTTP/3 peer-comparison benchmark (QUIC over UDP).
#
# The HTTP/3 sibling of bench/run_http.sh (HTTP/1.1) and bench/run_http2.sh
# (HTTP/2). Those scripts and their reports (HTTP_RESULTS.md,
# HTTP2_RESULTS.md) are not touched by this one; the three are meant to
# be read side by side.
#
# For each available HTTP/3 server implementation (NURL / Rust quinn+h3)
# this script:
#   1. Builds / preps the server binary
#   2. Starts it on its dedicated loopback port with the bench's
#      self-signed EC P-256 certificate
#   3. Waits until the QUIC listener answers (a short h2load --h3 probe)
#   4. For every cell "CxM" in $CELLS runs `h2load --h3` for $DURATION
#      seconds with C client connections and M concurrent streams each
#      (C*M requests in flight)
#   5. Kills the server
#   6. Captures requests/sec, p50 (h2load's "median") and p99 latency
#      and the mean from h2load's summary
#
# The NURL server additionally gets HTTP/2 reference rows at M=1 — the
# same binary, the same TLS listener, the same generator with
# `--alpn-list=h2` — so the two protocols' costs sit on one line; and a
# connection-setup row (one request per fresh connection) for both. No
# HTTP/1.1 rows: h2load's HTTP/1.1 mode paces itself (~2 ms per request)
# and would misreport that protocol; HTTP_RESULTS.md (oha) covers it.
#
# Load generator: h2load from nghttp2 built with ngtcp2 + nghttp3. The
# Ubuntu package is HTTP/2-only, so the generator runs from a docker
# image ($H2LOAD_IMAGE, default nghttp2-h3, built from nghttp2's own
# docker/Dockerfile — see .github/workflows/http3-bench.yml) unless
# $H2LOAD names a local binary that understands --h3.
#
# It then OVERWRITES bench/HTTP3_RESULTS.md with a fully generated report.
# That file is 100% generated — do not edit it by hand; the next run
# replaces it. Same contract as HTTP_RESULTS.md / HTTP2_RESULTS.md.
#
# Usage:
#   bench/run_http3.sh                        # defaults (see below)
#   DURATION=20 CELLS="1x1 10x10" bench/run_http3.sh
#   bench/run_http3.sh --cells "1x1 1x10 50x10"
#   bench/run_http3.sh --md /tmp/out.md       # write elsewhere
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH="$ROOT/bench"

DURATION="${DURATION:-10}"               # seconds per cell
CELLS="${CELLS:-1x1 1x10 1x100 10x1 10x10 50x1 50x10}"   # clients x streams
SETTLE_MS="${SETTLE_MS:-500}"            # post-start spin-up before bench
KILL_WAIT="${KILL_WAIT:-1}"              # post-bench grace before SIGKILL
ITERS="${ITERS:-3}"                      # measurement runs per cell, median wins
CONN_BURST="${CONN_BURST:-100}"          # connections per connection-setup run
MD_OUT="${MD_OUT:-$BENCH/HTTP3_RESULTS.md}"
H2LOAD_IMAGE="${H2LOAD_IMAGE:-nghttp2-h3}"

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
mkdir -p "$BENCH/_build"

# h2load with HTTP/3: a local binary that accepts --h3, else the docker image.
H2LOAD_CMD=()
H2LOAD_VERSION=""
if [[ -n "${H2LOAD:-}" && -x "${H2LOAD:-}" ]] && "$H2LOAD" --h3 --version >/dev/null 2>&1; then
    H2LOAD_CMD=("$H2LOAD")
    H2LOAD_VERSION="$("$H2LOAD" --version 2>&1 | head -1)"
elif command -v docker >/dev/null && docker image inspect "$H2LOAD_IMAGE" >/dev/null 2>&1; then
    H2LOAD_CMD=(docker run --rm --network=host "$H2LOAD_IMAGE" h2load)
    H2LOAD_VERSION="$(docker run --rm "$H2LOAD_IMAGE" h2load --version 2>&1 | head -1) (docker $H2LOAD_IMAGE)"
else
    echo "ERROR: no h2load with HTTP/3 support: set H2LOAD=/path/to/h2load (built with ngtcp2+nghttp3)" >&2
    echo "       or build the docker image: git clone --depth 1 -b v1.70.0 https://github.com/nghttp2/nghttp2 && docker build -t $H2LOAD_IMAGE -f nghttp2/docker/Dockerfile --build-arg NGHTTP2_BRANCH=v1.70.0 nghttp2" >&2
    exit 2
fi
echo "# h2load: $H2LOAD_VERSION" >&2

have_nurl=0; [[ -x "$NURLC" && -f "$RUNTIME" ]] && have_nurl=1
have_rs=0;   command -v cargo >/dev/null && have_rs=1
have_ssl=0;  command -v openssl >/dev/null && have_ssl=1

# Self-signed EC P-256 cert. Its own file pair, so this run never rewrites
# the ones bench/run_http.sh / run_http2.sh generate.
TLS_CERT="$BENCH/_build/tls3-cert.pem"
TLS_KEY="$BENCH/_build/tls3-key.pem"
have_tls=0
if (( have_ssl )); then
    if openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -nodes -keyout "$TLS_KEY" -out "$TLS_CERT" -days 3650 \
        -subj "/CN=localhost" \
        -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" >/dev/null 2>&1; then
        have_tls=1
    fi
fi
if (( ! have_tls )); then
    echo "ERROR: openssl could not generate the TLS cert QUIC needs" >&2
    exit 2
fi

# ── environment for the report header ───────────────────────────────
NURL_VERSION="$("$NURLC" --version 2>/dev/null | head -1)"
[[ -n "$NURL_VERSION" ]] || NURL_VERSION="$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null)"
RUSTC_VERSION="$(command -v rustc >/dev/null && rustc --version || echo 'n/a')"
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
# A QUIC listener has no TCP accept to probe: one tiny h2load run must
# complete a request.
wait_quic() {
    local port="$1" i
    for i in $(seq 1 40); do
        if "${H2LOAD_CMD[@]}" --h3 -n 1 -c 1 "https://127.0.0.1:$port/" 2>/dev/null \
             | grep -q '1 succeeded'; then
            return 0
        fi
        sleep 0.25
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

# h2load text summary → "rps p50_ms p99_ms mean_ms" (or FAILs when <99 %
# of requests succeeded). h2load prints the request-time row as
#   request     :  min  max  median  p95  p99  mean  sd  +/- sd
# with unit suffixes (us / ms / s).
_parse_h2load() {
    python3 - "$1" <<'PY'
import re, sys
txt = open(sys.argv[1], errors="replace").read()
def ms(tok):
    m = re.match(r'([0-9.]+)(us|ms|s)$', tok)
    if not m:
        return None
    v = float(m.group(1)); u = m.group(2)
    return v / 1000.0 if u == "us" else (v if u == "ms" else v * 1000.0)
m = re.search(r'requests: (\d+) total, (\d+) started, (\d+) done, (\d+) succeeded, (\d+) failed, (\d+) errored, (\d+) timeout', txt)
if not m:
    print("FAIL FAIL FAIL FAIL"); raise SystemExit
total, started, done, ok, failed, errored, timeout = map(int, m.groups())
if total == 0 or ok < 0.99 * total:
    print("FAIL FAIL FAIL FAIL"); raise SystemExit
r = re.search(r'finished in [0-9.]+(?:us|ms|s), ([0-9.]+) req/s', txt)
if not r:
    print("FAIL FAIL FAIL FAIL"); raise SystemExit
rps = float(r.group(1))
row = re.search(r'^request\s*:\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)', txt, re.M)
if not row:
    print("FAIL FAIL FAIL FAIL"); raise SystemExit
_mn, _mx, med, _p95, p99, mean = row.groups()
med, p99, mean = ms(med), ms(p99), ms(mean)
if None in (med, p99, mean):
    print("FAIL FAIL FAIL FAIL"); raise SystemExit
print(f"{rps:.0f} {med:.2f} {p99:.2f} {mean:.4f}")
PY
}

# One measured cell. proto = h3 | h2 | h1 (h2/h1 = reference runs on the
# same TLS listener through ALPN).
run_h2load() {
    local proto="$1" port="$2" conns="$3" streams="$4"
    local report="$BENCH/_build/h2load3-$proto-$port-c$conns-m$streams.txt"
    local flags=()
    case "$proto" in
        h3) flags+=(--h3) ;;
        h2) flags+=(--alpn-list=h2) ;;
        h1) flags+=(--alpn-list=http/1.1) ;;
    esac
    # short warm-up, then the timed run
    "${H2LOAD_CMD[@]}" "${flags[@]}" -D 1 -c "$conns" -m "$streams" \
        "https://127.0.0.1:$port/" >/dev/null 2>&1 || true
    "${H2LOAD_CMD[@]}" "${flags[@]}" -D "$DURATION" -c "$conns" -m "$streams" \
        "https://127.0.0.1:$port/" > "$report" 2>&1 \
        || { echo "FAIL FAIL FAIL FAIL"; return; }
    _parse_h2load "$report"
}

# Connection setup: CONN_BURST clients, one request each, fresh QUIC (or
# TLS) connection per request → connections per second.
run_connsetup() {
    local proto="$1" port="$2"
    local report="$BENCH/_build/h2load3-conn-$proto-$port.txt"
    local flags=()
    case "$proto" in
        h3) flags+=(--h3) ;;
        h2) flags+=(--alpn-list=h2) ;;
        h1) flags+=(--alpn-list=http/1.1) ;;
    esac
    "${H2LOAD_CMD[@]}" "${flags[@]}" -n "$CONN_BURST" -c "$CONN_BURST" -m 1 \
        "https://127.0.0.1:$port/" > "$report" 2>&1 \
        || { echo "FAIL"; return; }
    python3 - "$report" "$CONN_BURST" <<'PY'
import re, sys
txt = open(sys.argv[1], errors="replace").read(); n = int(sys.argv[2])
m = re.search(r'requests: (\d+) total, (\d+) started, (\d+) done, (\d+) succeeded', txt)
t = re.search(r'finished in ([0-9.]+)(us|ms|s),', txt)
if not m or not t or int(m.group(4)) < n:
    print("FAIL"); raise SystemExit
v = float(t.group(1)); u = t.group(2)
secs = v / 1e6 if u == "us" else (v / 1e3 if u == "ms" else v)
print(f"{n / secs:.0f}")
PY
}

median() {
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

measure_cell() {
    local proto="$1" port="$2" conns="$3" streams="$4"
    local rps_list=() p50_list=() p99_list=() mean_list=() i
    for i in $(seq 1 "$ITERS"); do
        local r rps p50 p99 mean
        r=$(run_h2load "$proto" "$port" "$conns" "$streams")
        read -r rps p50 p99 mean <<<"$r"
        if [[ "$rps" == "FAIL" ]]; then
            echo "FAIL FAIL FAIL FAIL"
            return
        fi
        rps_list+=("$rps"); p50_list+=("$p50"); p99_list+=("$p99"); mean_list+=("$mean")
    done
    echo "$(median_int "${rps_list[@]}") $(median "${p50_list[@]}") $(median "${p99_list[@]}") $(median "${mean_list[@]}")"
}

measure_conn() {
    local proto="$1" port="$2"
    local list=() i r
    for i in $(seq 1 "$ITERS"); do
        r=$(run_connsetup "$proto" "$port")
        [[ "$r" == "FAIL" ]] && { echo "FAIL"; return; }
        list+=("$r")
    done
    median_int "${list[@]}"
}

# ── servers ─────────────────────────────────────────────────────────
# The NURL peer is bench/http_server.nu unchanged — the HttpApp facade's
# TLS listener serves HTTP/3 on the same port over UDP (and HTTP/2 +
# HTTP/1.1 over TCP), so the very binary run_http.sh / run_http2.sh
# measure is the one measured here over QUIC.
NURL_BIN="$BENCH/_build/http_server_nurl_h3"
RUST_BIN="$BENCH/rust_http3_server/target/release/http3_server"

prep_nurl() {
    (( have_nurl )) || return 1
    local src="$BENCH/http_server.nu"
    local ll="$BENCH/_build/http_server_nurl_h3.ll"
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
    cargo build --release --manifest-path "$BENCH/rust_http3_server/Cargo.toml" 2>/dev/null
}

# run_server NAME PORT REF -- CMD...
#   REF = 1 → also the HTTP/2 / HTTP/1.1 reference rows and the
#   connection-setup rows for all three protocols (NURL only).
run_server() {
    local name="$1" port="$2" ref="$3"
    shift 3
    [[ "$1" == "--" ]] && shift
    local cmd=("$@")
    "${cmd[@]}" > "$BENCH/_build/${name}-h3.stdout.log" 2> "$BENCH/_build/${name}-h3.stderr.log" &
    local pid=$!
    if ! wait_quic "$port"; then
        local cell
        for cell in $CELLS; do echo "ROW $name ${cell%x*} ${cell#*x} FAIL FAIL FAIL FAIL"; done
        stop_pid "$pid"
        return
    fi
    sleep "$(python3 -c "print($SETTLE_MS / 1000.0)")"
    local cell
    for cell in $CELLS; do
        local conns="${cell%x*}" streams="${cell#*x}"
        echo "ROW $name $conns $streams $(measure_cell h3 "$port" "$conns" "$streams")"
    done
    if (( ref )); then
        local seen=" "
        for cell in $CELLS; do
            local conns="${cell%x*}" streams="${cell#*x}"
            [[ "$streams" == 1 ]] || continue
            [[ "$seen" == *" $conns "* ]] && continue
            seen="$seen$conns "
            echo "REF h2 $conns $(measure_cell h2 "$port" "$conns" 1)"
        done
        echo "CONN h3 $(measure_conn h3 "$port")"
        echo "CONN h2 $(measure_conn h2 "$port")"
    else
        echo "CONNPEER $name $(measure_conn h3 "$port")"
    fi
    stop_pid "$pid"
}

echo "# duration=${DURATION}s iters=${ITERS} cells=\"$CELLS\"" >&2

results=()
collect() { while read -r line; do results+=("$line"); done; }
na_rows() {
    local name="$1" cell
    for cell in $CELLS; do results+=("ROW $name ${cell%x*} ${cell#*x} n/a n/a n/a n/a"); done
}

nurl_ready=0; prep_nurl && nurl_ready=1
rust_ready=0; prep_rust && rust_ready=1

# Ports 18460 (NURL) / 18461 (Rust) — disjoint from the HTTP/1.1 and
# HTTP/2 benchmarks' ports.
if (( nurl_ready )); then collect < <(run_server nurl 18460 1 -- "$NURL_BIN" 18460 "$TLS_CERT" "$TLS_KEY"); else na_rows nurl; fi
if (( rust_ready )); then collect < <(run_server rust 18461 0 -- env TLS_CERT="$TLS_CERT" TLS_KEY="$TLS_KEY" TLS_PORT=18461 "$RUST_BIN"); else na_rows rust; fi

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
    printf 'ENV\th2load\t%s\n' "$H2LOAD_VERSION"
    printf 'ENV\tduration\t%s\n' "$DURATION"
    printf 'ENV\titers\t%s\n' "$ITERS"
    printf 'ENV\tcells\t%s\n' "$CELLS"
    printf 'ENV\tconn_burst\t%s\n' "$CONN_BURST"
    for row in "${results[@]}"; do
        printf '%s\n' "$row"
    done
} | python3 "$BENCH/gen_http3_results.py" > "$MD_OUT"
echo "wrote $MD_OUT" >&2
