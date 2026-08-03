#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/check_golden_twins.sh — a CHANGE-based gate for the Windows
#  golden corpus, exact where check_windows_goldens.sh is heuristic.
#
#  check_windows_goldens.sh catches the pure-growth shape (the Windows
#  golden is missing lines, adds none). It cannot catch line MUTATIONS:
#  when the MCP dual-era change rewrote result lines in mcp_basic /
#  mcp_http, the stale Windows twins differed with both '<' and '>'
#  lines — indistinguishable from a legitimate platform difference by
#  state alone, so the drift sailed through and broke the Windows run
#  on main.
#
#  The exact rule needs the CHANGE, not the state: for every golden
#  this commit range touches whose outputs-windows/ twin exists,
#
#    * twins byte-identical BEFORE the change  →  they must be
#      byte-identical AFTER it. Identical-before proves the test's
#      output is platform-independent, so the Linux update applies to
#      Windows verbatim — a copy the author forgot. HARD FAIL.
#
#    * twins already differed before  →  nothing can be verified from
#      Linux (the right Windows content needs a Windows runner). WARN
#      with the dispatch instructions, never fail.
#
#  Usage:   tools/check_golden_twins.sh [BASE_REF]
#  BASE_REF defaults to the merge base with origin/main. The pre-commit
#  hook applies the same rule to the staged diff (and auto-copies).
# ============================================================
set -u
cd "$(dirname "$0")/.."

LINUX_DIR=compiler/tests/outputs
WIN_DIR=compiler/tests/outputs-windows

BASE="${1:-}"
if [ -z "$BASE" ]; then
    BASE="$(git merge-base HEAD origin/main 2>/dev/null)" || BASE=""
    [ -n "$BASE" ] || BASE="HEAD~1"
fi
# The rule is vacuous when there is nothing between BASE and HEAD.
[ "$(git rev-parse "$BASE" 2>/dev/null)" = "$(git rev-parse HEAD)" ] && {
    echo "golden twins OK (no commits against $BASE)"; exit 0; }

fail=0
warned=0
while IFS= read -r f; do
    b="$(basename "$f")"
    w="$WIN_DIR/$b"
    [ -f "$w" ] || git cat-file -e "$BASE:$w" 2>/dev/null || continue
    old_l="$(git rev-parse --quiet --verify "$BASE:$f" 2>/dev/null || true)"
    old_w="$(git rev-parse --quiet --verify "$BASE:$w" 2>/dev/null || true)"
    if [ -n "$old_l" ] && [ "$old_l" = "$old_w" ]; then
        # Platform-independent output (twins identical before) — the
        # Windows twin must carry the same update.
        if ! cmp -s "$f" "$w"; then
            if [ "$fail" -eq 0 ]; then
                echo "Windows golden twins left behind by this change:" >&2
                echo "(twin was byte-identical to the Linux golden before the" >&2
                echo "change — the test's output is platform-independent, so" >&2
                echo "the update applies verbatim; copy it)" >&2
                echo >&2
            fi
            echo "  cp $f $w" >&2
            fail=1
        fi
    else
        # Twins differed already — a platform-specific test changed on
        # the Linux side. Can't be verified from Linux; say so once.
        if ! cmp -s "$f" "$w"; then
            if [ "$warned" -eq 0 ]; then
                echo "note: platform-specific goldens changed on the Linux side;" >&2
                echo "verify their Windows twins on a runner if the change touches" >&2
                echo "shared output (windows-tests.yml has a workflow_dispatch" >&2
                echo "input 'update_goldens' that regenerates the corpus):" >&2
                warned=1
            fi
            echo "  $w" >&2
        fi
    fi
done < <(git diff --name-only --diff-filter=ACM "$BASE"...HEAD -- "$LINUX_DIR/*.txt" 2>/dev/null \
         || git diff --name-only --diff-filter=ACM "$BASE" HEAD -- "$LINUX_DIR/*.txt")

if [ "$fail" -ne 0 ]; then
    echo >&2
    echo "Copy the Linux golden over each listed twin (the commit message" >&2
    echo "can say the output is platform-independent) and re-commit." >&2
    exit 1
fi
echo "golden twins OK"
