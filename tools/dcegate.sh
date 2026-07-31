#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/dcegate.sh — dead-function elimination gate.
#
#  nurlc emits only the functions `main` can reach. The corpus already
#  proves the pass never drops something that IS reachable — 567 tests
#  compile, link and run, and a wrongly-dropped function is an undefined
#  symbol at link time, not a silent miscompile. What the corpus cannot
#  see is the other half of the contract: a pass that decided everything
#  was reachable would still be green everywhere while quietly costing
#  nothing but wall clock.
#
#  That has already happened once. An off-by-one in the block scanner
#  made a `define` that followed a closing brace with no blank line
#  invisible, its body counted as module scope, and every function it
#  called became a root — examples/static_server.nu went from 947
#  droppable functions to 0 with every test still passing. This gate is
#  what would have caught it.
#
#  Checks, on compiler/tests/dce_reachability.nu:
#    1. `dead_weight` — called by nothing — is absent with the pass on
#       and present with `--no-dce`, so the pass is demonstrably running.
#    2. The four indirect-reachability routes survive: the dyn method
#       thunks named only by a module-scope vtable, the `% Drop` impl
#       reached through auto-drop, the lifted closure, and the generic
#       monomorphisation.
#    3. Both IRs link, and the two binaries print the same thing — the
#       pass changes what is emitted, never what it means.
#
#  Usage:  tools/dcegate.sh [source.nu]
#  Exit:   0 = pass · 1 = gate failure · 2 = precondition unmet
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NURLC="$ROOT/build/nurlc"
SRC="${1:-$ROOT/compiler/tests/dce_reachability.nu}"

[ -x "$NURLC" ] || { echo "dcegate: $NURLC missing — run ./build.sh first" >&2; exit 2; }
[ -f "$SRC" ]   || { echo "dcegate: source not found: $SRC" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$NURLC"          "$SRC" > "$tmp/dce.ll"  || { echo "dcegate: nurlc failed" >&2; exit 1; }
"$NURLC" --no-dce "$SRC" > "$tmp/full.ll" || { echo "dcegate: nurlc --no-dce failed" >&2; exit 1; }

fail=0
note() { echo "dcegate: FAIL — $1" >&2; fail=1; }

# Count `define`s whose function name contains $1.
count() { grep -c "^define[^@]*@[^ (]*$1" "$2" 2>/dev/null || true; }

n_full=$(grep -c '^define' "$tmp/full.ll" || true)
n_dce=$(grep -c '^define' "$tmp/dce.ll" || true)

# 1. The pass is running at all.
[ "$(count dead_weight "$tmp/full.ll")" -ge 1 ] || note "dead_weight missing from --no-dce output (fixture drifted?)"
[ "$(count dead_weight "$tmp/dce.ll")"  -eq 0 ] || note "unreachable dead_weight survived the pass"
[ "$n_dce" -lt "$n_full" ] || note "the pass dropped nothing ($n_full functions in, $n_dce out)"

# 2. The indirect routes survive. Each is reachable only through a
#    reference the pass has to find for itself.
for route in "__dynm:dyn method thunk (named only by a module-scope vtable)" \
             "drop__Tracked:user % Drop impl (called from auto-drop)" \
             "__closure:lifted closure body" \
             "twice__:generic monomorphisation"; do
    sym=${route%%:*}; what=${route#*:}
    [ "$(count "$sym" "$tmp/dce.ll")" -ge 1 ] || note "dropped a live function: $what"
done

# 3. Same program, either way.
for v in dce full; do
    clang -O2 -flto -Wl,--as-needed "$tmp/$v.ll" "$ROOT/stdlib/runtime.o" \
        -lm -lpthread $( [ "$(uname -s)" = Linux ] && echo -ldl ) \
        -o "$tmp/$v.bin" 2>"$tmp/$v.link" \
        || { note "$v.ll did not link"; sed -n '1,10p' "$tmp/$v.link" >&2; }
done
if [ -x "$tmp/dce.bin" ] && [ -x "$tmp/full.bin" ]; then
    "$tmp/dce.bin"  > "$tmp/dce.out"  2>&1
    "$tmp/full.bin" > "$tmp/full.out" 2>&1
    cmp -s "$tmp/dce.out" "$tmp/full.out" || {
        note "the two binaries print different things"
        diff "$tmp/full.out" "$tmp/dce.out" >&2
    }
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "dcegate: OK — $n_full functions emitted, $n_dce reachable from main; both builds behave identically"
