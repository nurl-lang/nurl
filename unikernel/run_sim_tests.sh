#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  unikernel/run_sim_tests.sh — the deterministic-simulation gate
#  (agora #260, DST 2/4).
#
#  A simulation is a program built with `build_nolibc.sh --sim`: the
#  cooperative runtime (threads and fibers as coroutines), a virtual
#  clock that jumps over idle time, and a seed that decides the schedule
#  and every random byte (unikernel/nolibc/sim.c). This gate asks the
#  four things a simulation must be, of each program it is given
#  (default: the simulated-network tests):
#
#    1. RIGHT: under several seeds its output is the hosted golden's
#       (compiler/tests/outputs/<name>.txt) — a different schedule is not
#       allowed to change what the program prints;
#    2. REPRODUCIBLE: one seed, run RUNS times, prints byte-identical
#       output and the same schedule hash — a failure found under a seed
#       replays exactly;
#    3. EXPLORING: where the run had a choice to make (two coroutines
#       runnable at once — the trace line's `choices`), the seeds do not
#       all give one schedule: a seed that changed nothing would test
#       nothing. A program that never has two runnable at once has one
#       schedule, and that is the right answer for it;
#    4. FASTER THAN TIME: the virtual time a run covers (its timeouts,
#       TCP's retransmissions) exceeds the wall-clock time it takes.
#
#  Usage:  unikernel/run_sim_tests.sh [test …]
#  Env:    SIM_SEEDS="1 2 3 4 5"   the seeds for 1 and 3
#          SIM_RUNS=20             the repetitions for 2
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$ROOT/compiler/tests"
OUT="$ROOT/build/nolibc-sim/bin"
SEEDS="${SIM_SEEDS:-1 2 3 4 5}"
RUNS="${SIM_RUNS:-20}"
mkdir -p "$OUT"
[ -x "$ROOT/build/nurlc" ] || { echo "run ./build.sh first" >&2; exit 2; }

names=("$@")
[ ${#names[@]} -gt 0 ] || names=(net_sim_http net_sim_http_async net_sim_seam)

fail=0
bad() { echo "  FAIL $1: $2"; fail=$((fail + 1)); }

# The golden's program output: everything after its OUTPUT line.
golden_output() { sed -n '/^OUTPUT$/,$p' "$TESTS/outputs/$1.txt" | tail -n +2; }
golden_exit()   { sed -n 's/^EXIT \(.*\)$/\1/p' "$TESTS/outputs/$1.txt"; }

for name in "${names[@]}"; do
    src="$TESTS/$name.nu"
    bin="$OUT/$name"
    [ -f "$src" ] || { bad "$name" "no such test"; continue; }
    if ! "$ROOT/unikernel/build_nolibc.sh" --sim "$src" -o "$bin" >"$OUT/$name.build.log" 2>&1; then
        bad "$name" "build failed ($OUT/$name.build.log)"
        continue
    fi
    want="$(golden_output "$name")"
    want_exit="$(golden_exit "$name")"

    # 1 + 3: right under every seed, and the seeds differ.
    traces=()
    choices=0
    for seed in $SEEDS; do
        got="$(NURL_SIM="$seed" "$bin" 2>/dev/null)"; code=$?
        [ "$got" = "$want" ] || { bad "$name" "seed $seed prints other than the golden"; diff <(echo "$want") <(echo "$got") | head -10 | sed 's/^/      /'; }
        [ "$code" = "$want_exit" ] || bad "$name" "seed $seed exits $code, the golden $want_exit"
        line="$(NURL_SIM="$seed" NURL_SIM_TRACE=1 "$bin" 2>&1 >/dev/null | grep '^nurl-sim:')"
        traces+=("$(echo "$line" | sed -n 's/.*trace=\([0-9a-f]*\).*/\1/p')")
        c="$(echo "$line" | sed -n 's/.*choices=\([0-9]*\).*/\1/p')"
        [ "${c:-0}" -gt "$choices" ] && choices="$c"
    done
    distinct="$(printf '%s\n' "${traces[@]}" | sort -u | grep -c .)"
    if [ "$choices" -gt 0 ] && [ "$distinct" -lt 2 ]; then
        bad "$name" "$choices choice points, and every seed made them alike (trace ${traces[0]})"
    fi

    # 2: one seed, RUNS times, byte for byte — stdout, stderr and the
    # schedule hash all included.
    first_seed="${SEEDS%% *}"
    ref="$(NURL_SIM="$first_seed" NURL_SIM_TRACE=1 "$bin" 2>&1)"
    same=1
    for _ in $(seq 2 "$RUNS"); do
        again="$(NURL_SIM="$first_seed" NURL_SIM_TRACE=1 "$bin" 2>&1)"
        [ "$again" = "$ref" ] || { same=0; break; }
    done
    [ "$same" = 1 ] || bad "$name" "seed $first_seed did not repeat itself over $RUNS runs"

    # 4: faster than the time it simulates.
    t0="$(date +%s%N)"
    vline="$(NURL_SIM="$first_seed" NURL_SIM_TRACE=1 "$bin" 2>&1 >/dev/null | grep '^nurl-sim:')"
    wall_ms=$(( ($(date +%s%N) - t0) / 1000000 ))
    virt_ms="$(echo "$vline" | sed -n 's/.*virtual_ms=\([0-9]*\).*/\1/p')"
    [ -n "$virt_ms" ] && [ "$virt_ms" -gt "$wall_ms" ] || bad "$name" "simulated ${virt_ms:-?} ms in $wall_ms ms of wall clock"

    echo "  ok   $name: ${#traces[@]} seeds, $distinct schedules ($choices choice points), $RUNS identical runs, ${virt_ms:-?} ms simulated in $wall_ms ms"
done

if [ "$fail" -gt 0 ]; then
    echo "run_sim_tests: $fail failure(s)"
    exit 1
fi
echo "run_sim_tests: all ok"
