#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  tools/nurlpkg/test-sim.sh — the gate for `nurlpkg test --sim`
#  (agora #261, DST 3/4), on the package in tools/nurlpkg/sim-fixture/:
#
#    1. a correct suite passes every seed — atomic_counter: N/N;
#    2. a racy test fails for SOME seeds, not all — racy_counter loses an
#       update only when the schedule runs both reads before either
#       write, so a seed sweep has to find it and FIFO alone is not the
#       whole story;
#    3. the seed it prints replays the failure exactly: the printed
#       `nurlpkg test --sim --seed S tests/racy_counter.nu` fails 10 times
#       out of 10, with byte-identical output each time.
#
#  Needs build/nurlc and build/nurlpkg (./build.sh) and Linux x86_64
#  (the simulation's runtime edge).
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIX="$ROOT/tools/nurlpkg/sim-fixture"
SEEDS="${SIM_SEEDS:-40}"
[ -x "$ROOT/build/nurlc" ] && [ -x "$ROOT/build/nurlpkg" ] || { echo "run ./build.sh first" >&2; exit 2; }

fail=0
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
cd "$FIX" || exit 2
export NURL_CC="$ROOT/nurl.sh"

sweep="$("$ROOT/build/nurlpkg" test --sim --seeds "$SEEDS" 2>/dev/null)"
echo "$sweep" | sed 's/^/    /'

# 1. The correct suite: every seed.
echo "$sweep" | grep -q "PASS atomic_counter ($SEEDS/$SEEDS seeds)" \
    || bad "atomic_counter did not pass all $SEEDS seeds"

# 2. The racy test: some seeds, not all.
line="$(echo "$sweep" | grep 'FAIL racy_counter')"
[ -n "$line" ] || bad "racy_counter passed every seed — the sweep found nothing"
passed="$(echo "$line" | sed -n 's/.*(\([0-9]*\)\/[0-9]* seeds).*/\1/p')"
[ -n "$passed" ] && [ "$passed" -gt 0 ] || bad "racy_counter failed under every seed (want: some)"

# 3. Its replay line, exactly as printed, fails the same way 10/10.
replay="$(echo "$sweep" | sed -n 's/^ *replay: nurlpkg //p' | head -1)"
if [ -z "$replay" ]; then
    bad "no replay line printed"
else
    # shellcheck disable=SC2086
    ref="$("$ROOT/build/nurlpkg" $replay 2>&1)"; code=$?
    [ "$code" -ne 0 ] || bad "the replay ($replay) passed"
    for _ in $(seq 2 10); do
        # shellcheck disable=SC2086
        again="$("$ROOT/build/nurlpkg" $replay 2>&1)"
        [ "$again" = "$ref" ] || { bad "the replay ($replay) did not repeat itself"; break; }
    done
    echo "  replay: nurlpkg $replay — failed 10/10, identically"
fi

if [ "$fail" -gt 0 ]; then
    echo "test-sim: $fail failure(s)"
    exit 1
fi
echo "test-sim: all ok"
