#!/usr/bin/env bash
# bench/run.sh — compile + run each benchmark in every available
# language and report median wall-clock time over N runs.
#
# Usage:    ./bench/run.sh [N]                  (default N=5)
#           ./bench/run.sh --bench sum_n        (single bench)
#
# Outputs a Markdown table; pipe into bench/RESULTS.md to update.
#
# Tools:    nurlc (built into ./build/), python3, rustc (optional),
#           node (optional). Missing tools are reported as "n/a".
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH="$ROOT/bench"
BUILD="$BENCH/_build"
mkdir -p "$BUILD"

ITERS=5
BENCH_FILTER=""
PER_RUN_TIMEOUT=30   # seconds — a slow language gets "TIMEOUT" instead
                     # of hanging the suite. Tuned so a 5-bench × 4-lang
                     # × 5-run matrix completes in well under 30 min
                     # even when one cell hits the cap every time.
while (( $# > 0 )); do
    case "$1" in
        --bench)   BENCH_FILTER="$2"; shift 2 ;;
        --timeout) PER_RUN_TIMEOUT="$2"; shift 2 ;;
        [0-9]*)    ITERS="$1"; shift ;;
        *)         echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# ── tool detection ───────────────────────────────────────────────
NURLC="$ROOT/build/nurlc"
RUNTIME="$ROOT/stdlib/runtime.o"
have_nurl=0; [[ -x "$NURLC" && -f "$RUNTIME" ]] && have_nurl=1
have_py=0;   command -v python3 >/dev/null && have_py=1
have_rs=0;   command -v rustc   >/dev/null && have_rs=1
have_js=0;   command -v node    >/dev/null && have_js=1

# Lib detection for the runtime link line (mirrors compiler/tests/run_tests.sh).
CURL_LIBS=""; [[ -f "$ROOT/stdlib/runtime.curl"    ]] && CURL_LIBS="$(pkg-config --libs libcurl 2>/dev/null)"
SSL_LIBS="";  [[ -f "$ROOT/stdlib/runtime.openssl" ]] && SSL_LIBS="$(pkg-config --libs openssl 2>/dev/null)"
SQ_LIBS="";   [[ -f "$ROOT/stdlib/runtime.sqlite3" ]] && SQ_LIBS="$(pkg-config --libs sqlite3 2>/dev/null)"
PQ_LIBS="";   [[ -f "$ROOT/stdlib/runtime.pq"      ]] && PQ_LIBS="$(pkg-config --libs libpq 2>/dev/null)"
Z_LIBS="";    [[ -f "$ROOT/stdlib/runtime.z"       ]] && Z_LIBS="$(pkg-config --libs zlib 2>/dev/null)"
ZSTD_LIBS=""; [[ -f "$ROOT/stdlib/runtime.zstd"    ]] && ZSTD_LIBS="$(pkg-config --libs libzstd 2>/dev/null)"

# ── helpers ──────────────────────────────────────────────────────
# Print one wall-clock ms reading on stdout. On non-zero exit prints
# FAIL; on `timeout` SIGTERM (exit 124) prints "TIMEOUT" so the median
# helper can render it as a distinct cell.
time_ms() {
    local label="$1"; shift
    local t0 t1 ec
    t0=$(date +%s%N)
    timeout --foreground "${PER_RUN_TIMEOUT}s" "$@" > /dev/null 2>&1
    ec=$?
    t1=$(date +%s%N)
    if [[ $ec -eq 0 ]]; then
        echo $(( (t1 - t0) / 1000000 ))
    elif [[ $ec -eq 124 ]]; then
        echo TIMEOUT
    else
        echo FAIL
    fi
}

# Median of a list of integers. If any element is TIMEOUT we report
# the median as ">${PER_RUN_TIMEOUT}s" (the cell hit the cap and the
# real number is unbounded). FAIL propagates likewise.
median() {
    local args=("$@")
    for a in "${args[@]}"; do
        [[ "$a" == FAIL    ]] && { echo FAIL; return; }
        [[ "$a" == TIMEOUT ]] && { echo ">${PER_RUN_TIMEOUT}s"; return; }
    done
    printf '%s\n' "${args[@]}" | sort -n | awk '
        { a[NR]=$1 }
        END { if (NR % 2) print a[(NR+1)/2]; else print a[NR/2] }
    '
}

# ── compile / prepare each benchmark ─────────────────────────────
compile_nurl() {
    local name="$1"
    local src="$BENCH/$name.nu"
    local ll="$BUILD/$name.ll"
    local bin="$BUILD/${name}_nurl"
    "$NURLC" "$src" > "$ll" 2>"$BUILD/$name.nurl.err" || return 1
    clang -O2 -flto "$ll" "$RUNTIME" -lm -lpthread \
        $CURL_LIBS $SSL_LIBS $SQ_LIBS $PQ_LIBS $Z_LIBS $ZSTD_LIBS \
        -o "$bin" 2>"$BUILD/$name.link.err" || return 1
    echo "$bin"
}
compile_rs() {
    local name="$1"
    local src="$BENCH/$name.rs"
    local bin="$BUILD/${name}_rs"
    rustc -O "$src" -o "$bin" 2>"$BUILD/$name.rs.err" || return 1
    echo "$bin"
}

# ── data gen for json_parse ──────────────────────────────────────
if (( have_py )) && [[ ! -f "$BENCH/data.json" ]]; then
    python3 "$BENCH/gen_data.py"
fi

# ── benchmark roster ─────────────────────────────────────────────
BENCHES=(lcg sieve json_parse)
[[ -n "$BENCH_FILTER" ]] && BENCHES=("$BENCH_FILTER")

# ── report ───────────────────────────────────────────────────────
printf '\n# Bench results — %s × %s runs each, median wall-clock ms\n' \
       "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ITERS"
printf '\n%-14s | %10s | %10s | %10s | %10s\n' "bench" "NURL" "Python" "Rust" "Node"
printf '%-14s-+-%10s-+-%10s-+-%10s-+-%10s\n' "--------------" "----------" "----------" "----------" "----------"

for b in "${BENCHES[@]}"; do
    # NURL
    nurl_bin=""
    if (( have_nurl )) && [[ -f "$BENCH/$b.nu" ]]; then
        nurl_bin=$(compile_nurl "$b") || nurl_bin=""
    fi
    # Rust
    rs_bin=""
    if (( have_rs )) && [[ -f "$BENCH/$b.rs" ]]; then
        rs_bin=$(compile_rs "$b") || rs_bin=""
    fi

    # Collect runs
    declare -a nurl_runs py_runs rs_runs js_runs
    nurl_runs=(); py_runs=(); rs_runs=(); js_runs=()
    for ((r=0; r<ITERS; r++)); do
        [[ -n "$nurl_bin" ]] && nurl_runs+=("$(time_ms nurl   "$nurl_bin")") || nurl_runs+=(FAIL)
        [[ -f "$BENCH/$b.py" && $have_py == 1 ]] && py_runs+=("$(cd "$ROOT" && time_ms py python3 "$BENCH/$b.py")") || py_runs+=(FAIL)
        [[ -n "$rs_bin" ]] && rs_runs+=("$(cd "$ROOT" && time_ms rs "$rs_bin")") || rs_runs+=(FAIL)
        [[ -f "$BENCH/$b.js" && $have_js == 1 ]] && js_runs+=("$(cd "$ROOT" && time_ms js node "$BENCH/$b.js")") || js_runs+=(FAIL)
    done
    nurl_med=$(median "${nurl_runs[@]}")
    py_med=$(median "${py_runs[@]}")
    rs_med=$(median "${rs_runs[@]}")
    js_med=$(median "${js_runs[@]}")
    printf '%-14s | %10s | %10s | %10s | %10s\n' "$b" "$nurl_med" "$py_med" "$rs_med" "$js_med"
done
echo
