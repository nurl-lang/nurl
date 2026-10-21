#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/unsafe_report.sh — `nurlc --unsafe-report` lists the
#  whole surface a reviewer has to trust (docs/MEMORY.md §6.4).
#
#  unsafe_report_surface.nu holds one of everything the report lists and
#  several things it must not. The report goes to stderr, which the test
#  suite's goldens do not capture for a program that compiles, so it is
#  checked here: every expected line present, and exactly those lines —
#  a report that also listed the standard library's own assertions, or
#  a marker that only adds checks, would bury the surface it is for.
#
#  Exit 0 iff every assertion holds.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
SRC="compiler/tests/unsafe_report_surface.nu"

[ -x "$NURLC" ] || { echo "unsafe_report: $NURLC not found — run ./build.sh" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0
note() { printf '  %-52s %s\n' "$1" "$2"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }

(cd "$ROOT" && NURL_STDLIB="$ROOT" "$NURLC" --unsafe-report "$SRC") > "$WORK/r.ll" 2> "$WORK/r.err" \
    || { echo "unsafe_report: compiling $SRC failed:"; cat "$WORK/r.err"; exit 1; }

want=(
    "$SRC:15 % Send Wrapper"
    "$SRC:19 % Sync Guarded"
    "$SRC:29 & atoi: in text"
    "$SRC:31 & memchr: nocapture buf"
    "$SRC:33 & nurl_atomic_i64_inc: sync p"
    "$SRC:37 parse_num"
)
for w in "${want[@]}"; do
    if grep -qxF "$w" "$WORK/r.err"; then note "${w#$SRC:}" "ok"; else bad "${w#$SRC:}" "not in the report"; fi
done
n=$(grep -c . "$WORK/r.err")
if [ "$n" -eq "${#want[@]}" ]; then note "nothing else listed" "ok"; else
    bad "nothing else listed" "$n lines, expected ${#want[@]}:"; sed 's/^/      /' "$WORK/r.err"
fi

# A program that asks for no trust says so.
printf '@ main → i { ^ 0 }\n' > "$WORK/none.nu"
(cd "$ROOT" && NURL_STDLIB="$ROOT" "$NURLC" --unsafe-report "$WORK/none.nu") > /dev/null 2> "$WORK/n.err"
if grep -q '^unsafe: none' "$WORK/n.err"; then note "a safe program: none" "ok"; else bad "a safe program: none" "$(head -1 "$WORK/n.err")"; fi

[ "$fails" -eq 0 ] && echo "unsafe_report: all assertions hold" || echo "unsafe_report: $fails FAILED"
exit "$fails"
