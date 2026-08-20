#!/usr/bin/env bash
# bench/run_pq.sh — post-quantum crypto peer-comparison benchmark.
#
# Builds and runs the two PQ harnesses:
#   bench/pq_compare.nu   pure-NURL stdlib (std/mlkem, std/mldsa,
#                         std/slhdsa, std/hash_sha3)
#   bench/rust_pq         pure-Rust RustCrypto (ml-kem, ml-dsa, slh-dsa,
#                         shake)
#
# Each harness emits one `ROW\t<name>\t<ns_per_op>\t<iters>` line per
# operation (plus a `THR` line for SHAKE bulk throughput). Both are run
# $RUNS times; the report takes the median per operation. It then
# OVERWRITES bench/PQ_RESULTS.md with a fully generated report. That
# file is 100% generated — do not edit it by hand; the next run replaces
# it. This is the same contract bench/HTTP_RESULTS.md has with
# bench/run_http.sh.
#
# Usage:
#   bench/run_pq.sh                # defaults
#   RUNS=5 bench/run_pq.sh
#   bench/run_pq.sh --md /tmp/out.md
#
# One full run is ~25 s of measurement per repetition (the SLH-DSA
# signing ops dominate), so the default 3 repetitions finish in well
# under five minutes including both builds.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH="$ROOT/bench"

RUNS="${RUNS:-3}"                        # repetitions per harness, median wins
MD_OUT="${MD_OUT:-$BENCH/PQ_RESULTS.md}"

while (( $# > 0 )); do
    case "$1" in
        --runs) RUNS="$2"; shift 2 ;;
        --md)   MD_OUT="$2"; shift 2 ;;
        *)      echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

NURLC="$ROOT/build/nurlc"
have_nurl=0; [[ -x "$NURLC" ]] && have_nurl=1
have_rs=0;   command -v cargo >/dev/null && have_rs=1

# ── environment (mirrors run_http.sh, for the generated report) ─────
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

# ── build both harnesses ────────────────────────────────────────────
NURL_BIN="$BENCH/_build/pq_compare"
RUST_BIN="$BENCH/rust_pq/target/release/pq_bench"

nurl_ready=0
if (( have_nurl )); then
    # nurl.sh is the standard compile+link driver (resolves stdlib
    # imports relative to $ROOT, links runtime.o with the right libs).
    if ( cd "$ROOT" && ./nurl.sh -O2 bench/pq_compare.nu "$NURL_BIN" >&2 ); then
        nurl_ready=1
    fi
fi

rust_ready=0
if (( have_rs )); then
    if cargo build --release --manifest-path "$BENCH/rust_pq/Cargo.toml" >&2; then
        rust_ready=1
    fi
fi

# RustCrypto crate versions, for the report's implementation table.
crate_version() {
    grep -A1 "^name = \"$1\"" "$BENCH/rust_pq/Cargo.lock" 2>/dev/null \
        | grep '^version' | head -1 | sed 's/version = "\(.*\)"/\1/'
}
RS_MLKEM="$(crate_version ml-kem)"
RS_MLDSA="$(crate_version ml-dsa)"
RS_SLHDSA="$(crate_version slh-dsa)"
RS_SHAKE="$(crate_version shake)"

# ── run: $RUNS repetitions per harness, rows tagged with the impl ───
results=()
collect() { local impl="$1"; while IFS= read -r line; do results+=("$line	$impl"); done; }

run_impl() {   # <impl> <ready> <cmd...>
    local impl="$1" ready="$2"; shift 2
    if (( ! ready )); then
        echo "# $impl: not available — its column will be n/a" >&2
        return
    fi
    local i
    for i in $(seq 1 "$RUNS"); do
        echo "# $impl run $i/$RUNS" >&2
        collect "$impl" < <("$@")
    done
}

run_impl nurl "$nurl_ready" "$NURL_BIN"
run_impl rust "$rust_ready" "$RUST_BIN"

# ── generate the report ─────────────────────────────────────────────
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
    printf 'ENV\truns\t%s\n' "$RUNS"
    printf 'ENV\trs_mlkem\t%s\n' "$RS_MLKEM"
    printf 'ENV\trs_mldsa\t%s\n' "$RS_MLDSA"
    printf 'ENV\trs_slhdsa\t%s\n' "$RS_SLHDSA"
    printf 'ENV\trs_shake\t%s\n' "$RS_SHAKE"
    # ROW/THR lines already carry their tag; collect() appended the impl.
    for row in "${results[@]}"; do
        printf '%s\n' "$row"
    done
} | python3 "$BENCH/gen_pq_results.py" > "$MD_OUT"

echo "wrote $MD_OUT" >&2
