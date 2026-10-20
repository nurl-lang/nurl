#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  check_diag_nurl_types.sh — a diagnostic speaks NURL types.
#
#  The compiler types values by their LLVM lowering, and a message that
#  interpolated that string as is told a reader who wrote `vec_get` that
#  an operand was '{ i1, i64 }', a binding 'i64*', a struct '%Fruit'.
#  llvm_to_nurl spells every one of them the way the source does ('?i',
#  '*i', 'Fruit'); this gate keeps a new message from forgetting to.
#
#  Reads the committed goldens' `error:` / `warning:` lines (the
#  diagnostics the corpus pins) and fails on a quoted LLVM aggregate
#  ('{ i1, …'), a quoted lowered scalar ('i64', 'i8*', 'double') or a
#  quoted '%Name' type. A trait OBJECT is written '%Trait' in NURL, so
#  a quote that follows "a '%" in prose about dynamic objects is
#  allowed by name: messages that mention a dyn object say 'object'.
#
#  Run from the repo root:  ./tools/check_diag_nurl_types.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."

bad=$(grep -hE '(error|warning): ' compiler/tests/outputs/*.txt \
    | grep -E "'\{ i[0-9]+, |'(i64|i8\*|double|i64\*)'|'%[A-Za-z_][A-Za-z0-9_]*\*?'" \
    | grep -vE "'%[A-Za-z_]+' (object|dispatch)|object-safe for '%|into a '%[A-Za-z_]+' object|'%' in a type position|Wanted '%|'%[A-Za-z_]+' is a dynamic trait object|through a '%[A-Za-z_]+' object" )
if [ -n "$bad" ]; then
    echo "check_diag_nurl_types: diagnostics print lowered LLVM types — spell them with llvm_to_nurl:" >&2
    printf '%s\n' "$bad" | cut -c1-240 >&2
    exit 1
fi
echo "diagnostics speak NURL types (no lowered LLVM type in any golden's error/warning line)"
