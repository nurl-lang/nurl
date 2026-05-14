#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/nurlfmt_idempotent.sh — verify that nurlfmt is
#  deterministic AND semantically transparent across the entire
#  NURL source tree.
#
#  Two invariants are checked per file:
#
#    1. IDEMPOTENCE
#       fmt(fmt(x)) ==byte== fmt(x)
#       The formatter must be a fixed point on its own output.
#
#    2. IR EQUIVALENCE
#       nurlc(fmt(x)) ==byte== nurlc(x)
#       Reformatting must not change a single byte of the LLVM IR
#       the compiler emits. Catches inadvertent semantics drift
#       (lost-or-introduced whitespace that crosses a token
#       boundary, lost negative-literal vs binary-minus, etc.).
#
#  Tree coverage:
#    * stdlib/        — every shipped module
#    * examples/      — every demo program
#    * compiler/tests/ — every regression case
#    * compiler/nurlc.nu — the bootstrap compiler itself
#
#  Files that the compiler cannot lex on their own (e.g. partial
#  include fragments that depend on an outer module) are skipped
#  for the IR-equivalence check by listing them in $SKIP_IR. They
#  still go through idempotence.
#
#  Exit codes:
#    0 — both invariants hold on every covered file
#    1 — at least one violation; full diff printed to stdout
#    2 — environment problem (nurlfmt or nurlc missing)
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

NURLFMT="$ROOT_DIR/build/nurlfmt"
NURLC="$ROOT_DIR/build/nurlc"

if [[ ! -x "$NURLFMT" ]]; then
    echo "ERROR: $NURLFMT not found. Run ./tools/nurlfmt/build.sh first." >&2
    exit 2
fi
if [[ ! -x "$NURLC" ]]; then
    echo "ERROR: $NURLC not found. Run ./build.sh first." >&2
    exit 2
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Files whose nurlc IR cannot be obtained standalone (include-only
# fragments, modules whose top-level relies on outer-module imports,
# etc). Idempotence is still checked; IR equivalence is skipped.
SKIP_IR_PATTERNS=(
    # Anything under tools/nurlfmt/ that we author here imports
    # other tools/nurlfmt/ modules — the standalone path works for
    # nurlfmt.nu (the entry point) but not the helper files.
    "tools/nurlfmt/tokenize.nu"
    "tools/nurlfmt/pretty.nu"
)

should_skip_ir() {
    local rel="$1"
    for pat in "${SKIP_IR_PATTERNS[@]}"; do
        if [[ "$rel" == "$pat" ]]; then return 0; fi
    done
    return 1
}

# Collect every .nu file under the covered trees, sorted for
# determinism.
mapfile -t FILES < <(
    {
        find stdlib            -name '*.nu' -type f
        find examples          -name '*.nu' -type f
        find compiler/tests    -name '*.nu' -type f
        find tools/nurlfmt     -name '*.nu' -type f
        echo compiler/nurlc.nu
        echo compiler/nurlc_lastgood.nu
    } | sort -u
)

TOTAL=${#FILES[@]}
FAIL_IDEMP=()
FAIL_IR=()
SKIPPED_IR=0
CHECKED=0

# Allow callers to focus on a single file for fast iteration.
if [[ $# -ge 1 ]]; then
    FILES=("$@")
    TOTAL=${#FILES[@]}
fi

for rel in "${FILES[@]}"; do
    [[ -f "$rel" ]] || continue
    CHECKED=$((CHECKED + 1))

    # ── Invariant 1: idempotence ─────────────────────────────────
    PASS1="$TMPDIR/pass1.nu"
    PASS2="$TMPDIR/pass2.nu"
    if ! "$NURLFMT" "$rel" >"$PASS1" 2>/dev/null; then
        FAIL_IDEMP+=("$rel  (pass 1 failed to format)")
        continue
    fi
    if ! "$NURLFMT" "$PASS1" >"$PASS2" 2>/dev/null; then
        FAIL_IDEMP+=("$rel  (pass 2 failed to format)")
        continue
    fi
    if ! cmp -s "$PASS1" "$PASS2"; then
        FAIL_IDEMP+=("$rel")
        diff -u "$PASS1" "$PASS2" | head -40 > "$TMPDIR/last_idemp.diff"
        continue
    fi

    # ── Invariant 2: IR equivalence ──────────────────────────────
    if should_skip_ir "$rel"; then
        SKIPPED_IR=$((SKIPPED_IR + 1))
        continue
    fi

    IR_ORIG="$TMPDIR/orig.ll"
    IR_FMT="$TMPDIR/fmt.ll"

    if ! "$NURLC" "$rel"   >"$IR_ORIG" 2>/dev/null; then
        # The original itself doesn't compile standalone (probably a
        # fragment). Skip the IR pass without flagging.
        SKIPPED_IR=$((SKIPPED_IR + 1))
        continue
    fi
    if ! "$NURLC" "$PASS1" >"$IR_FMT"  2>/dev/null; then
        FAIL_IR+=("$rel  (formatted source failed to compile)")
        continue
    fi
    if ! cmp -s "$IR_ORIG" "$IR_FMT"; then
        FAIL_IR+=("$rel")
        diff -u "$IR_ORIG" "$IR_FMT" | head -60 > "$TMPDIR/last_ir.diff"
    fi
done

# ── Report ───────────────────────────────────────────────────────
echo "nurlfmt round-trip:"
echo "  checked         : $CHECKED files"
echo "  ir-equiv covered: $((CHECKED - ${#FAIL_IDEMP[@]} - SKIPPED_IR))"
echo "  ir-equiv skipped: $SKIPPED_IR"
echo "  idempotence FAIL: ${#FAIL_IDEMP[@]}"
echo "  ir-equiv    FAIL: ${#FAIL_IR[@]}"

if (( ${#FAIL_IDEMP[@]} == 0 && ${#FAIL_IR[@]} == 0 )); then
    echo "OK — nurlfmt is idempotent and IR-transparent across the covered tree."
    exit 0
fi

if (( ${#FAIL_IDEMP[@]} > 0 )); then
    echo ""
    echo "── Idempotence failures (top 20) ─────────────────────"
    printf '  %s\n' "${FAIL_IDEMP[@]:0:20}"
    if [[ -f "$TMPDIR/last_idemp.diff" ]]; then
        echo ""
        echo "  diff sample:"
        sed 's/^/    /' "$TMPDIR/last_idemp.diff"
    fi
fi
if (( ${#FAIL_IR[@]} > 0 )); then
    echo ""
    echo "── IR-equivalence failures (top 20) ──────────────────"
    printf '  %s\n' "${FAIL_IR[@]:0:20}"
    if [[ -f "$TMPDIR/last_ir.diff" ]]; then
        echo ""
        echo "  diff sample:"
        sed 's/^/    /' "$TMPDIR/last_ir.diff"
    fi
fi
exit 1
