#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/journal_null_ir.sh — no panic-journal call on a pointer
#  that is null on every path (agora #282).
#
#  A function handing back a raw pointer (`vec_data [u]`, `→ *T`) has no
#  owner to hand over, and a raw-pointer binding of one (`: ~ *u dst (
#  vec_data … )`) owns no string. Before, the first loaded its null owner
#  slot and called nurl_journal_forget on it at every return, and the
#  second freed and journaled a null slot. Both calls are external (the
#  runtime is not inlined under NURL_LTO=full or a split build), so every
#  Vec-heavy encoder paid them. journal_null_ir.nu runs the program (its
#  golden); this reads its IR.
#  Exit 0 iff every assertion holds.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
SRC="$SCRIPT_DIR/journal_null_ir.nu"

[ -x "$NURLC" ] || { echo "journal_null_ir: $NURLC not found — run ./build.sh" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0
note() { printf '  %-52s %s\n' "$1" "$2"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }

(cd "$ROOT" && NURL_STDLIB="$ROOT" "$NURLC" "$SRC") > "$WORK/j.ll" 2> "$WORK/j.err" \
    || { echo "journal_null_ir: compiling $SRC failed:"; cat "$WORK/j.err"; exit 1; }

# body <fn> — the IR of function @__nurl_fn.<fn>.
body() { awk "/^define .*@__nurl_fn\\.$1\\(/,/^}/" "$WORK/j.ll"; }

# none <label> <fn> <regex> — the function exists and no line of it matches.
none() {
    local b n
    b=$(body "$2")
    [ -n "$b" ] || { bad "$1" "no function $2 in the IR"; return; }
    n=$(printf '%s\n' "$b" | grep -cE "$3")
    if [ "$n" -eq 0 ]; then note "$1" "ok"; else bad "$1" "$n line(s) match /$3/"; fi
}

none "vec_data: no journal_forget of its null owner" vec_data__u8 'call void @nurl_journal_forget\('
none "fill: no journal_push of a raw-pointer binding" fill 'call void @nurl_journal_push\('
none "fill: no free of a raw-pointer binding's slot" fill 'call void @nurl_free\('

[ "$fails" -eq 0 ] && echo "journal_null_ir: all checks passed" || { echo "journal_null_ir: $fails check(s) failed"; exit 1; }
