#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  bench/chaincheck.sh — physical-floor verification.
#
#  A benchmark row whose blurb claims a loop-carried dependency chain
#  must not run faster than the chain's hardware minimum — a cell below
#  that line means the compiler shortcut the recurrence (as LLVM used to
#  do to the pre-xorshift lcg/affine_mix by composing k affine steps
#  into one) and the row no longer measures what it says.
#
#  For every row with a well-defined serial chain this script builds the
#  NURL, C and Rust binaries the way bench.sh does and asserts each one
#  runs no faster than its documented floor, in one of two modes:
#
#  * PMU mode (workstations): retired user-mode cycles via
#    `perf stat -e cycles:u` — cycles, not wall time, so CPU frequency
#    drops out — must satisfy  cycles/iterations >= floor(cyc/iter).
#    A PASS margin under ~10 % means the row runs *at* its dependency
#    chain, the strongest honesty statement a serial benchmark can make.
#
#  * wall-clock mode (CI: GitHub Actions / Azure VMs do not expose the
#    PMU, `perf stat` reports <not supported>): the measured wall time
#    must be >= iterations x floor cycles at MAX_GHZ, a frequency no
#    current CPU exceeds. Coarser, but still catches every real
#    violation ever seen here — the old composed lcg (100M iters in
#    3.7 ms) would need a 162 GHz clock to be honest.
#
#  The floors are per-iteration critical-path latencies on current
#  x86-64 cores (imul 3, simple ALU op 1, LEA-fused shift+add 1; a
#  32-bit op's & 0xffffffff mask is free via implicit zero-extension).
#
#  Usage:  ./bench/chaincheck.sh          # auto-detects the mode
#  Needs:  nurlc, clang, rustc; perf only for PMU mode.
# ============================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH="$ROOT/bench"
BUILD="$BENCH/_build"
mkdir -p "$BUILD"

MAX_GHZ=6.0   # no shipping CPU sustains more; a cell needing >6 GHz is dishonest

NURLC="$ROOT/build/nurlc"
RUNTIME="$ROOT/stdlib/runtime.o"
[[ -x "$NURLC" && -f "$RUNTIME" ]] || { echo "chaincheck: need build/nurlc (run ./build.sh)" >&2; exit 1; }

MODE="${CHAINCHECK_MODE:-}"   # pmu | wall | empty = auto-detect
if [[ -z "$MODE" ]]; then
    MODE=wall
    if perf stat -e cycles:u true >/dev/null 2>&1 \
       && ! perf stat -e cycles:u true 2>&1 | grep -q "not supported"; then
        MODE=pmu
    fi
fi
echo "chaincheck: mode=$MODE (pmu = exact cycles; wall = lower bound at ${MAX_GHZ} GHz)"

# row  iterations  floor(cyc/iter)  chain
# Rows without a strict serial chain (independent iterations, memory-
# bound scans, allocator work) have no hard floor and are not listed.
FLOORS="\
lcg               20000000   6   imul(3)+add(1)+shr(1)+xor(1)
affine_mix        20000000   6   lea(1)+and(1)+shr(1)+xor(1)+lea(1)+and(1)
packet_classifier 25000000   4   imul32(3)+add(1), branch resolution on top
ring_write        20000000   6   imul32(3)+add(1)+shr(1)+xor(1), store off-chain
histogram_bins    20000000   6   imul32(3)+add(1)+shr(1)+xor(1), RMW on top
prefix_scan        1000000  16   16 dependent adds per scan
sort_window        2000000  26   13-stage compare/exchange network, 2 cyc/stage"

cycles_of() {  # <bin> -> min cycles:u of 3 runs, empty on failure
    local best=999999999999 c r
    for r in 1 2 3; do
        c="$(perf stat -e cycles:u -x, "$1" 2>&1 >/dev/null | head -1 | cut -d, -f1)"
        [[ "$c" =~ ^[0-9]+$ ]] || { echo ""; return; }
        (( c < best )) && best=$c
    done
    echo "$best"
}

wall_ms_of() {  # <bin> -> min wall ms of 3 runs (EPOCHREALTIME, no forks)
    local best=999999 t0 t1 ms r
    for r in 1 2 3; do
        t0=$EPOCHREALTIME; "$1" >/dev/null 2>&1 || { echo ""; return; }; t1=$EPOCHREALTIME
        ms="$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.3f", (b - a) * 1000 }')"
        best="$(awk -v x="$ms" -v y="$best" 'BEGIN { print (x < y) ? x : y }')"
    done
    echo "$best"
}

fail=0
if [[ $MODE == pmu ]]; then
    printf '%-18s %-5s %14s %10s %8s  %s\n' row lang cycles cyc/iter floor verdict
else
    printf '%-18s %-5s %12s %14s  %s\n' row lang wall_ms floor_ms@6GHz verdict
fi

while read -r name iters floor chain; do
    [[ -z "$name" ]] && continue
    ( cd "$ROOT" && "$NURLC" "bench/$name.nu" > "$BUILD/$name.chk.ll" \
        && clang -O2 -flto -Wl,--as-needed "$BUILD/$name.chk.ll" "$RUNTIME" \
                 -lm -lpthread -o "$BUILD/$name.chk.nurl" ) 2>/dev/null \
        || { echo "chaincheck: NURL build failed for $name" >&2; fail=1; continue; }
    clang -O2 "$BENCH/$name.c" -lm -o "$BUILD/$name.chk.c" 2>/dev/null \
        || { echo "chaincheck: C build failed for $name" >&2; fail=1; continue; }
    rustc -C opt-level=2 "$BENCH/$name.rs" -o "$BUILD/$name.chk.rs" 2>/dev/null \
        || { echo "chaincheck: Rust build failed for $name" >&2; fail=1; continue; }

    for pair in "nurl:$BUILD/$name.chk.nurl" "c:$BUILD/$name.chk.c" "rust:$BUILD/$name.chk.rs"; do
        lang="${pair%%:*}"; bin="${pair#*:}"
        if [[ $MODE == pmu ]]; then
            cyc="$(cd "$ROOT" && cycles_of "$bin")"
            [[ -z "$cyc" ]] && { echo "chaincheck: perf failed on $name/$lang" >&2; fail=1; continue; }
            verdict="$(awk -v c="$cyc" -v n="$iters" -v f="$floor" \
                'BEGIN { print (c / n >= f * 0.97) ? "PASS" : "BELOW-FLOOR" }')"
            [[ "$verdict" != PASS ]] && fail=1
            awk -v r="$name" -v l="$lang" -v c="$cyc" -v n="$iters" -v f="$floor" -v v="$verdict" \
                'BEGIN { printf "%-18s %-5s %14d %10.2f %8d  %s\n", r, l, c, c/n, f, v }'
        else
            ms="$(cd "$ROOT" && wall_ms_of "$bin")"
            [[ -z "$ms" ]] && { echo "chaincheck: run failed on $name/$lang" >&2; fail=1; continue; }
            verdict="$(awk -v t="$ms" -v n="$iters" -v f="$floor" -v g="$MAX_GHZ" \
                'BEGIN { print (t >= n * f / (g * 1e6)) ? "PASS" : "BELOW-FLOOR" }')"
            [[ "$verdict" != PASS ]] && fail=1
            awk -v r="$name" -v l="$lang" -v t="$ms" -v n="$iters" -v f="$floor" -v g="$MAX_GHZ" -v v="$verdict" \
                'BEGIN { printf "%-18s %-5s %12.2f %14.2f  %s\n", r, l, t, n * f / (g * 1e6), v }'
        fi
    done
done <<< "$FLOORS"

if (( fail )); then
    echo
    echo "chaincheck: FAIL — a cell is running below its dependency-chain floor;"
    echo "the compiler has shortcut the recurrence and the row is not measuring"
    echo "what its blurb claims. Fix the kernel (see how lcg's xorshift mix"
    echo "breaks affine composition) before publishing numbers."
    exit 1
fi
echo
echo "chaincheck: all rows at or above their dependency-chain floors."
