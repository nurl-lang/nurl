#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/check_windows_goldens.sh — catch a Windows golden that went
#  stale, from Linux.
#
#  compiler/tests/outputs-windows/ is a parallel golden corpus, and
#  windows-tests.yml runs on pushes to MAIN rather than per-PR (the
#  Windows runner is the slowest leg). So a PR that adds assertions to a
#  test updates outputs/ and the Windows copy silently keeps the old
#  expectation — the break surfaces one push later, on main, to whoever
#  pushed next.
#
#  That is exactly what happened to float_extra: erf/erfc added seven
#  lines in July, the Windows golden was written in June, and Windows CI
#  reported `PASS 537 · FAIL 1` weeks afterwards.
#
#  The shape is recognisable without a Windows machine: the Windows
#  golden is missing lines the Linux one has, and adds none of its own.
#  A genuine platform difference shows up as Windows-ONLY lines, or as a
#  mix — those are left alone (24 of them today, all legitimate).
#
#  If a test ever legitimately produces FEWER lines on Windows, add its
#  basename to PURE_DELETION_OK below with a note saying why.
#
#  Run from the repo root:  ./tools/check_windows_goldens.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."

LINUX_DIR=compiler/tests/outputs
WIN_DIR=compiler/tests/outputs-windows

# Basenames whose Windows golden is legitimately a subset of the Linux one.
PURE_DELETION_OK=""

fail=0
checked=0
for f in "$LINUX_DIR"/*.txt; do
    b="$(basename "$f")"
    w="$WIN_DIR/$b"
    # No Windows golden at all = the test is skipped there; not our business.
    [ -f "$w" ] || continue
    checked=$((checked + 1))
    cmp -s "$f" "$w" && continue
    d="$(diff "$f" "$w")"
    # Windows-only lines present → a real platform difference, leave it.
    printf '%s\n' "$d" | grep -q '^>' && continue
    case " $PURE_DELETION_OK " in *" $b "*) continue ;; esac
    if [ "$fail" -eq 0 ]; then
        echo "Windows goldens missing lines the Linux goldens have:" >&2
        echo "(the Windows copy was not updated when the test grew)" >&2
        echo >&2
    fi
    echo "  $WIN_DIR/$b" >&2
    printf '%s\n' "$d" | sed 's/^/      /' >&2
    fail=1
done

if [ "$fail" -ne 0 ]; then
    cat >&2 <<'EOF'

Fix: if the test's output is platform-independent (pass/fail labels, no
raw floats or paths), copy the Linux golden over the Windows one and say
so in the commit. If it is not, regenerate on a real runner —
windows-tests.yml has a workflow_dispatch input `update_goldens` that
rewrites the corpus and uploads it as an artifact to review and commit.
EOF
    exit 1
fi

echo "windows goldens OK ($checked pairs; none missing lines)"
