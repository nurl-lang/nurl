#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  check_strict_arity.sh — no first-party file may contain the
#  n-ary `&`/`|` arity trap.
#
#  `? & a b c d { then } { else }` reads as a four-way AND and is
#  not one: `&` is BINARY, so it takes `a b`, then `c` and `d` are
#  consumed as the bare then/else values and the two blocks that
#  follow run as plain statements. The conditional logic is wrong
#  and the compiler still emits a working binary — nothing
#  downstream can tell, which is what makes it worth a gate.
#
#  nurlc warns about this by default (so third-party trees keep
#  building) and errors under --strict-arity. This script runs the
#  strict compiler over every first-party .nu file.
#
#  It found the shape it was written for on its first run:
#  examples/audio_sparcles2.nu culled EVERY particle on every frame
#  because the off-screen test's second half had been swallowed and
#  the kill ran unconditionally.
#
#  Usage:
#    ./tools/check_strict_arity.sh            # whole first-party tree
#    ./tools/check_strict_arity.sh FILE…      # just those files
#
#  Exit codes:
#    0 — clean
#    1 — at least one file carries the trap (offenders listed)
#    2 — environment problem (nurlc missing)
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

NURLC="$ROOT_DIR/build/nurlc"
if [[ ! -x "$NURLC" ]]; then
    echo "ERROR: $NURLC not found. Run ./build.sh first." >&2
    exit 2
fi

if [[ $# -ge 1 ]]; then
    FILES=("$@")
else
    mapfile -t FILES < <(
        {
            find stdlib         -name '*.nu' -type f
            find examples       -name '*.nu' -type f
            find compiler/tests -name '*.nu' -type f
            find tools          -name '*.nu' -type f
            find nurlapi        -name '*.nu' -type f
            find packages       -name '*.nu' -type f -not -path '*/deps/*'
            echo compiler/nurlc.nu
        } | sort -u
    )
fi

# compiler/tests/ carries fixtures whose JOB is to be wrong — including
# this diagnostic's own regression, so without an exclusion the gate
# flags the test that proves the gate works.
#
# Ask the GOLDEN, not the name. A golden whose first line is
# "COMPILE FAIL" marks a test the corpus expects the compiler to reject;
# run_san_tests.sh chose that rule for exactly this reason ("and
# whatever tomorrow's negative test is called"). A name list would be
# the fourth copy in this repo, and the copy that gets forgotten fails
# in a way that reads as a real defect.
is_deliberate_failure() {
    case "$1" in
        compiler/tests/*) ;;
        *) return 1 ;;
    esac
    local base golden
    base="$(basename "$1" .nu)"
    golden="$ROOT_DIR/compiler/tests/outputs/$base.txt"
    [[ -f "$golden" ]] || return 1
    case "$(head -n 1 "$golden")" in
        "COMPILE FAIL"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Only the arity diagnostic counts. A file that fails to compile for an
# unrelated reason (a package module that needs its deps/ resolved, say)
# is not this gate's business — it has its own.
OFFENDERS=()
SKIPPED=0
for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || continue
    if is_deliberate_failure "$f"; then SKIPPED=$((SKIPPED + 1)); continue; fi
    hit="$("$NURLC" --strict-arity "$f" 2>&1 >/dev/null \
           | grep -F "consumed bare then/else values" || true)"
    if [[ -n "$hit" ]]; then
        OFFENDERS+=("$hit")
    fi
done

if (( ${#OFFENDERS[@]} > 0 )); then
    echo "ERROR: the n-ary '&'/'|' arity trap is present in ${#OFFENDERS[@]} place(s):" >&2
    printf '%s\n' "${OFFENDERS[@]}" >&2
    echo >&2
    echo "Each '&' and '|' takes exactly TWO operands. For n conditions write" >&2
    echo "n-1 of them up front:  ? & & & a b c d { then } { else }" >&2
    exit 1
fi

echo "strict-arity: OK — $(( ${#FILES[@]} - SKIPPED )) files carry no arity trap ($SKIPPED deliberate-failure fixtures skipped)."
