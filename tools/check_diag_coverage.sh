#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  check_diag_coverage.sh — every diagnostic nurlc can print must be
#  something a test has actually made it print.
#
#  The `ax` goal is that a model handed a compile error learns the rule
#  and the fix from the message alone. Source scans got that goal most
#  of the way: they can count whether a message names a cure, states a
#  rule, shows a spelling. What they cannot see is whether the message
#  is ever REACHED — and an unreached message is unverified in every way
#  that matters:
#
#    * its wording has never been read next to the program that caused
#      it, which is how the one FALSE message (bool→int return, fixed in
#      ecc058c) survived a source scan that scored it as excellent;
#    * its line and caret placement have never been checked;
#    * it may be dead outright, preempted by a looser check upstream, in
#      which case the good message is written but the user gets the
#      generic one;
#    * nothing stops a later edit from gutting it, because no golden
#      holds its text.
#
#  So this gate compiles the corpus, captures every diagnostic, and
#  matches them back to their source sites. Sites nobody made speak are
#  listed. The count is RATCHETED against a committed baseline: existing
#  gaps do not fail the build, but a new die site added without a test
#  that fires it does. A diagnostic is not finished when it is written —
#  it is finished when something has read it.
#
#  Usage:
#    ./tools/check_diag_coverage.sh              # ratchet check
#    ./tools/check_diag_coverage.sh --report     # list the gaps
#    ./tools/check_diag_coverage.sh --update     # re-baseline
#
#  Exit codes:
#    0 — coverage at or better than the baseline
#    1 — new never-fired diagnostics appeared (they are listed)
#    2 — environment problem (nurlc missing, no python3)
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

NURLC="$ROOT_DIR/build/nurlc"
SRC="$ROOT_DIR/compiler/nurlc.nu"
ERRDIR="$ROOT_DIR/build/diagcov"
BASELINE="$SCRIPT_DIR/diag_coverage_baseline.txt"
ANALYZE="$SCRIPT_DIR/diag_coverage.py"

MODE="check"
case "${1:-}" in
    --report) MODE="report" ;;
    --update) MODE="update" ;;
    "")       ;;
    *) echo "usage: $0 [--report|--update]" >&2; exit 2 ;;
esac

[[ -x "$NURLC" ]] || { echo "error: $NURLC not built — run ./build.sh" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not on PATH" >&2; exit 2; }

# ── capture ─────────────────────────────────────────────────────
# The corpus is compiler/tests: it is the set whose outcomes are
# already baselined, so every diagnostic it raises is one the project
# has committed to. --lint is on so the lint-only diagnostics count as
# exercised too. Failures are the point here, so no `set -e`.
rm -rf "$ERRDIR"
mkdir -p "$ERRDIR"
for src in "$ROOT_DIR"/compiler/tests/*.nu; do
    name="$(basename "$src" .nu)"
    "$NURLC" --lint "$src" >/dev/null 2>"$ERRDIR/$name.err"
done

# Probe programs live beside the corpus and exist only to make a
# diagnostic speak; they are not compiled by the test runner.
if [[ -d "$ROOT_DIR/compiler/tests/diagprobes" ]]; then
    for src in "$ROOT_DIR"/compiler/tests/diagprobes/*.nu; do
        [[ -e "$src" ]] || continue
        name="probe_$(basename "$src" .nu)"
        "$NURLC" --lint "$src" >/dev/null 2>"$ERRDIR/$name.err"
    done
fi

# ── analyse ─────────────────────────────────────────────────────
if [[ "$MODE" == "update" ]]; then
    python3 "$ANALYZE" "$SRC" "$ERRDIR" fingerprints > "$BASELINE" || exit 2
    python3 "$ANALYZE" "$SRC" "$ERRDIR" summary
    echo "baseline updated: $BASELINE"
    exit 0
fi

python3 "$ANALYZE" "$SRC" "$ERRDIR" "$MODE" || exit 2

[[ -f "$BASELINE" ]] || { echo "error: no baseline — run $0 --update" >&2; exit 2; }

# Ratchet on identity, not on count: a message may be rewritten (its key
# changes) without the total moving, and that new wording is just as
# unread as a brand-new site. Compare the key sets.
CUR="$(mktemp)"; trap 'rm -f "$CUR"' EXIT
python3 "$ANALYZE" "$SRC" "$ERRDIR" fingerprints > "$CUR" || exit 2

NEW="$(comm -13 <(cut -d' ' -f1 "$BASELINE" | sort) <(cut -d' ' -f1 "$CUR" | sort))"
if [[ -n "$NEW" ]]; then
    echo
    echo "error: diagnostics that no test makes the compiler print:"
    while read -r key; do
        [[ -n "$key" ]] && grep -- "^$key " "$CUR" | sed 's/^/    /'
    done <<< "$NEW"
    echo
    echo "  Write a program in compiler/tests/ that triggers each one, read what"
    echo "  the compiler actually says, and keep it as a diag_* test (the runner"
    echo "  baselines the diagnostic TEXT for that prefix — should_fail_* records"
    echo "  only COMPILE FAIL and would not hold the wording)."
    echo "  If a message is genuinely unreachable, delete it rather than baseline it."
    echo "  To accept deliberately: ./tools/check_diag_coverage.sh --update"
    exit 1
fi

FIXED="$(comm -23 <(cut -d' ' -f1 "$BASELINE" | sort) <(cut -d' ' -f1 "$CUR" | sort) | wc -l)"
if [[ "$FIXED" -gt 0 ]]; then
    echo
    echo "$FIXED baselined gap(s) now covered — re-baseline with --update to lock it in."
fi
echo "diagnostic coverage: no new never-fired sites."
exit 0
