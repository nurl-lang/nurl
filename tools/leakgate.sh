#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/leakgate.sh — self-compile leak-freedom gate.
#
#  `nurlc compiler/nurlc.nu` must leak NOTHING. The July 2026 campaign
#  took that compile from 2,793,226 leaked allocations / 33.4 MB to zero
#  (peak RSS 115.9 -> 18.5 MB); this gate is what keeps it there. Leak
#  freedom is a property that decays one unowned helper at a time, and
#  every step of the campaign found leaks that had sat unnoticed for
#  months — nothing in CI was looking.
#
#  Hard gate: ANY LeakSanitizer report fails, no allowance, no budget.
#  A leak is not a threshold to stay under, it is a bug to not have.
#  ASan and UBSan findings fail it too — the compile is instrumented, so
#  a use-after-free or UB in the same run is free signal.
#
#  Usage:  tools/leakgate.sh [source.nu]
#    source.nu   what to compile (default: compiler/nurlc.nu — the
#                self-compile, the largest NURL program that exists)
#
#  Pre-req: ./build.sh --san --no-tests, so build/nurlc and
#  stdlib/runtime.o carry the sanitizer instrumentation. Like
#  run_san_tests.sh this script DOES NOT rebuild — keep concerns
#  separate, and never silently gate an uninstrumented binary (which
#  would pass every time while checking nothing).
#
#  Exit:  0 = zero leaks · 1 = leaks/sanitizer findings · 2 = harness
#         precondition unmet (no sanitized build)
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NURLC="$ROOT/build/nurlc"
RUNTIME="$ROOT/stdlib/runtime.o"
SRC="${1:-$ROOT/compiler/nurlc.nu}"

[ -x "$NURLC" ] || { echo "leakgate: $NURLC missing — run ./build.sh --san --no-tests first" >&2; exit 2; }
[ -f "$SRC" ]   || { echo "leakgate: source not found: $SRC" >&2; exit 2; }

# An uninstrumented build would sail through this gate reporting nothing,
# which is the one failure mode a leak gate must not have. Both the
# runtime object and the linked compiler have to carry ASan.
# (grep -c, not grep -q: -q closes the pipe on its first match, and under
# `pipefail` nm's SIGPIPE would fail the test that just succeeded.)
if [ "$(nm "$RUNTIME" 2>/dev/null | grep -c "asan_init")" -eq 0 ]; then
    echo "leakgate: $RUNTIME was not built with -fsanitize=address." >&2
    echo "          Run ./build.sh --san --no-tests to rebuild it." >&2
    exit 2
fi
if [ "$( { nm -D "$NURLC" 2>/dev/null; nm "$NURLC" 2>/dev/null; } | grep -c "asan_init")" -eq 0 ]; then
    echo "leakgate: $NURLC is not sanitizer-instrumented." >&2
    echo "          Run ./build.sh --san --no-tests to rebuild it." >&2
    exit 2
fi

ir="$(mktemp)"
err="$(mktemp)"
trap 'rm -f "$ir" "$err"' EXIT

echo "leakgate: $NURLC ${SRC#"$ROOT"/} under ASan+LSan"

# exitcode=23 is LSan's own convention for "leaks were found"; spelling it
# out keeps the verdict readable when a future ASan default changes.
ASAN_OPTIONS="detect_leaks=1:exitcode=23:abort_on_error=0:halt_on_error=0:print_stacktrace=1" \
UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=0" \
    "$NURLC" "$SRC" > "$ir" 2> "$err"
rc=$?

# A sanitizer finding of any kind fails the gate. Checked before the exit
# code so a leak report reads as a leak report rather than "exit 23".
if grep -qE "LeakSanitizer|AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:" "$err"; then
    echo "leakgate: FAIL — the self-compile is not clean."
    echo
    summary="$(grep -E "^SUMMARY: " "$err" | head -1)"
    [ -n "$summary" ] && echo "  $summary" && echo
    echo "  first findings (full report above the summary in the log):"
    head -60 "$err" | sed 's/^/  /'
    echo
    echo "  Leak freedom here is absolute — there is no budget to raise."
    echo "  Reproduce locally: ./build.sh --san --no-tests && tools/leakgate.sh"
    echo "  Each frame names the NURL function that allocated; the usual"
    echo "  cause is a helper whose result is fresh but is not declared"
    echo "  owning, so no consumer ever releases it."
    exit 1
fi

if [ "$rc" -ne 0 ]; then
    echo "leakgate: FAIL — the compile itself failed (exit $rc):"
    tail -20 "$err" | sed 's/^/  /'
    exit 1
fi

# Zero stderr and exit 0 could also mean "compiled nothing at all", which
# is exactly how a broken gate looks green. Assert real IR came out.
ir_bytes="$(wc -c < "$ir")"
if [ "$ir_bytes" -lt 100000 ]; then
    echo "leakgate: FAIL — only $ir_bytes bytes of IR emitted; the compile did not run to completion." >&2
    exit 1
fi

if [ -s "$err" ]; then
    echo "leakgate: note — compiler stderr was not empty:"
    head -20 "$err" | sed 's/^/  /'
fi

echo "leakgate: OK — zero leaks, ${ir_bytes} bytes of IR emitted"
