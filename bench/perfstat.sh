#!/usr/bin/env bash
# bench/perfstat.sh — build the u64 micro set with the current `build/nurlc`
# and report retired instructions and core cycles for each binary.
#
# Why not wall clock: `bench/bench.sh` measures the whole process with
# a millisecond-ish resolution and several per cent of run-to-run drift, so
# anything under ~10 % there is indistinguishable from noise (the first
# report of this set showed `histogram_bins` at 1.15× against C when the
# two binaries retire the same instructions in the same cycles). Retired
# instructions and cycles are counted by the CPU itself: instructions are
# essentially deterministic for these single-threaded kernels, and cycles
# do not move with the frequency governor. That makes a 1 % change
# meaningful and a regression impossible to miss.
#
# Usage:
#   ./bench/perfstat.sh                     # build + measure, print a table
#   ./bench/perfstat.sh --save ref.tsv      # also write the raw numbers
#   ./bench/perfstat.sh --against ref.tsv   # compare against a saved run
#   ./bench/perfstat.sh --reps 15           # perf repetitions (default 10)
#   ./bench/perfstat.sh --cpu 4             # pin to a core (default: none)
#   ./bench/perfstat.sh --no-build          # measure what is already built
#
# The build directory is bench/_build/perf, kept apart from bench.sh's.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH="$ROOT/bench"
BUILD="$BENCH/_build/perf"
NURLC="$ROOT/build/nurlc"
RUNTIME="$ROOT/stdlib/runtime.o"
CLANG="${CLANG:-clang}"

REPS=10
SAVE=""
AGAINST=""
CPU=""
DO_BUILD=1

# The roster comes from bench/manifest.tsv, the same list bench.sh times,
# so a benchmark added or retired there shows up here without a second
# edit.
BENCHES=()
while IFS=$'\t' read -r name _rest; do
    [[ -z "${name:-}" || "$name" == \#* ]] && continue
    BENCHES+=("$name")
done < "$BENCH/manifest.tsv"

while (( $# > 0 )); do
    case "$1" in
        --reps)     REPS="$2"; shift 2 ;;
        --save)     SAVE="$2"; shift 2 ;;
        --against)  AGAINST="$2"; shift 2 ;;
        --cpu)      CPU="$2"; shift 2 ;;
        --bench)    BENCHES=("$2"); shift 2 ;;
        --no-build) DO_BUILD=0; shift ;;
        -h|--help)  sed -n '2,26p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *)          echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

mkdir -p "$BUILD"
PIN=(); [[ -n "$CPU" ]] && PIN=(taskset -c "$CPU")

if (( DO_BUILD )); then
    for n in "${BENCHES[@]}"; do
        printf '  …building %s\r' "$n" >&2
        ( cd "$ROOT" && "$NURLC" "$BENCH/$n.nu" > "$BUILD/$n.ll" ) || { echo "$n: nurlc FAILED" >&2; exit 1; }
        "$CLANG" -O2 -flto -Wl,--as-needed "$BUILD/$n.ll" "$RUNTIME" -lm -lpthread \
                 -o "$BUILD/${n}_nu" 2>/dev/null || { echo "$n: link FAILED" >&2; exit 1; }
    done
    printf '                              \r' >&2
fi

# The checksum gate, cheaply: every binary must still print the same line
# it printed before. A speed number for a program that stopped computing
# the right thing is worthless.
declare -A INSTR CYCLES SUMS
for n in "${BENCHES[@]}"; do
    printf '  …measuring %s\r' "$n" >&2
    SUMS[$n]=$(cd "$ROOT" && "$BUILD/${n}_nu")
    out=$("${PIN[@]}" perf stat -r "$REPS" -x, -e instructions,cycles "$BUILD/${n}_nu" 2>&1)
    INSTR[$n]=$(awk -F, '/instructions/{print $1}' <<< "$out")
    CYCLES[$n]=$(awk -F, '/cycles/{print $1}' <<< "$out")
done
printf '                              \r' >&2

if [[ -n "$AGAINST" ]]; then
    declare -A REF_I REF_C REF_S
    while IFS=$'\t' read -r n i c s; do
        REF_I[$n]=$i; REF_C[$n]=$c; REF_S[$n]=$s
    done < "$AGAINST"
    printf '%-20s %14s %14s %8s %14s %14s %8s %s\n' \
        benchmark instr ref_instr Δ cycles ref_cycles Δ checksum
    for n in "${BENCHES[@]}"; do
        di="—"; dc="—"; ck="—"
        [[ -n "${REF_I[$n]:-}" ]] && di=$(awk -v a="${INSTR[$n]}" -v b="${REF_I[$n]}" 'BEGIN{printf "%+.2f%%",(a/b-1)*100}')
        [[ -n "${REF_C[$n]:-}" ]] && dc=$(awk -v a="${CYCLES[$n]}" -v b="${REF_C[$n]}" 'BEGIN{printf "%+.2f%%",(a/b-1)*100}')
        [[ -n "${REF_S[$n]:-}" ]] && { [[ "${SUMS[$n]}" == "${REF_S[$n]}" ]] && ck="ok" || ck="CHANGED"; }
        printf '%-20s %14s %14s %8s %14s %14s %8s %s\n' \
            "$n" "${INSTR[$n]}" "${REF_I[$n]:-—}" "$di" \
            "${CYCLES[$n]}" "${REF_C[$n]:-—}" "$dc" "$ck"
    done
else
    printf '%-20s %14s %14s  %s\n' benchmark instructions cycles checksum
    for n in "${BENCHES[@]}"; do
        printf '%-20s %14s %14s  %s\n' "$n" "${INSTR[$n]}" "${CYCLES[$n]}" "${SUMS[$n]}"
    done
fi

if [[ -n "$SAVE" ]]; then
    : > "$SAVE"
    for n in "${BENCHES[@]}"; do
        printf '%s\t%s\t%s\t%s\n' "$n" "${INSTR[$n]}" "${CYCLES[$n]}" "${SUMS[$n]}" >> "$SAVE"
    done
    echo "saved → $SAVE" >&2
fi
