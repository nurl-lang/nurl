#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  check_diag_anchor.sh — a diagnostic must point at the mistake.
#
#  check_diag_coverage.sh answers "has anything ever printed this?".
#  It cannot answer "did it point at the right thing?", and the two
#  failures are not equally bad: a precise message against the wrong
#  line is worse for a reader than a vague message against the right
#  one, because it sends them somewhere real to look for a problem that
#  is not there.
#
#  The mechanically-wrong case needs no annotation to detect. Many
#  checks can only fire once their operands have been consumed, and by
#  then the lexer sits past the statement — so `die lex` anchors on
#  whatever came next. When the mistake is in a function's LAST
#  statement, what came next is the closing brace, and the compiler
#  prints a caret under a `}`:
#
#      diag_closure_arity_few.nu:9:1: error: call to 'f' passes 1 …
#      }
#      ^
#
#  `}` is never the subject of a diagnostic. `die_stmt` (anchor at the
#  statement) and `die_pos` (anchor at a captured token) exist to
#  prevent exactly this; nine sites had not been told to use them.
#
#  Reads the committed goldens rather than recompiling — they already
#  hold the location, the echoed line and the caret, so the check is
#  instant and runs on every diagnostic the corpus has baselined.
#
#  Genuinely unterminated constructs are exempt by message text: when
#  the closer is what went missing, end-of-input IS the subject.
#
#  Usage:
#    ./tools/check_diag_anchor.sh             # gate
#    ./tools/check_diag_anchor.sh --report    # list offenders
#
#  Exit codes:
#    0 — every baselined diagnostic anchors on real code
#    1 — at least one anchors on a closing delimiter (listed)
#    2 — environment problem (no python3)
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

command -v python3 >/dev/null 2>&1 || { echo "error: python3 not on PATH" >&2; exit 2; }

OUT="$(python3 "$SCRIPT_DIR/check_diag_anchor.py" compiler/tests report)" || exit 2
COUNT="$(sed -n 's/^mis-anchored diagnostics: //p' <<< "$OUT")"

if [[ "${COUNT:-1}" -ne 0 ]]; then
    echo "$OUT"
    echo
    echo "error: $COUNT diagnostic(s) do not point at the mistake."
    echo "  The check fires after its operands are consumed, so 'die lex' lands"
    echo "  on the next token — the '}' when the mistake is the last statement."
    echo "  Switch the site to 'die_stmt' (anchors at the statement start) or to"
    echo "  'die_pos' (anchors at a position captured before advancing), then"
    echo "  re-mint the golden with run_tests.sh --update."
    exit 1
fi

[[ "${1:-}" == "--report" ]] && echo "$OUT"
echo "diagnostic anchors: every baselined diagnostic points at real code."
exit 0
