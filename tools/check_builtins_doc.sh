#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/check_builtins_doc.sh — assert that the documentation
#  module stdlib/core/builtins.nu stays in sync with the runtime
#  preamble the compiler emits into every program.
#
#  stdlib/core/builtins.nu exists so the pre-registered C-runtime
#  surface (nurl_str_float, nurl_println, …) is DISCOVERABLE —
#  nurldoc renders it, nurl_api indexes it, nurl_grep sees it. It is
#  hand-written (the doc prose is the point), so it can drift from
#  the authoritative list: the `__emit_rt_decl syms `declare …``
#  lines inside emit_header in compiler/nurlc.nu. This gate fails
#  when the two disagree.
#
#  Direction 1: every preamble symbol must be documented in
#  builtins.nu, unless listed in SKIP below (compiler/IR machinery a
#  user never calls, or shapes NURL FFI cannot spell).
#  Direction 2: every FFI name in builtins.nu must exist in the
#  preamble — no stale entries after a runtime removal.
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Deliberately undocumented preamble symbols:
#   llvm.dbg.declare       — LLVM debug-info intrinsic, not callable
#   nurl_init              — argv stash called by the generated main()
#   nurl_journal_*         — panic-unwind allocation journal (compiler-emitted)
#   nurl_vec_drop          — compiler-emitted container destructor hook
#   printf                 — variadic libc; documented C everywhere
#   strtod                 — i8** out-param; use float.nu's checked parsers
SKIP='^(llvm\.dbg\.declare|nurl_init|nurl_journal_push|nurl_journal_push_drop|nurl_journal_forget|nurl_vec_drop|printf|strtod)$'

preamble="$(grep -oE '__emit_rt_decl syms `declare [^`]+' compiler/nurlc.nu \
  | grep -oE '@[A-Za-z0-9_.]+' | sed 's/^@//' | sort -u)"

documented="$(grep -oE '^& `c` @ [A-Za-z0-9_]+' stdlib/core/builtins.nu \
  | awk '{ print $4 }' | sort -u)"

missing="$(comm -23 <(echo "$preamble" | grep -Ev "$SKIP") <(echo "$documented"))"
stale="$(comm -13 <(echo "$preamble") <(echo "$documented"))"

status=0
if [ -n "$missing" ]; then
    echo "ERROR: preamble builtins missing from stdlib/core/builtins.nu:" >&2
    echo "$missing" | sed 's/^/  /' >&2
    echo "Document them there (or add to SKIP in $0 with a reason)." >&2
    status=1
fi
if [ -n "$stale" ]; then
    echo "ERROR: stdlib/core/builtins.nu documents symbols the compiler preamble no longer declares:" >&2
    echo "$stale" | sed 's/^/  /' >&2
    echo "Remove them from builtins.nu." >&2
    status=1
fi

if [ "$status" -eq 0 ]; then
    n="$(echo "$documented" | wc -l)"
    echo "OK: stdlib/core/builtins.nu documents all $n non-skipped preamble builtins."
fi
exit "$status"
