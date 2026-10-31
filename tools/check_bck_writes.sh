#!/usr/bin/env bash
# ============================================================
#  tools/check_bck_writes.sh — every write to the borrow checker's
#  side tables goes through bck_put / bck_add_word / bck_add.
#
#  A `~` loop's fixpoint (bck_loop) is reached only when the next walk
#  of its body would repeat one already made: same state, same facts in
#  g_bck. While a loop is walked, the wrappers keep g_bck_dg, a digest of
#  the whole table's content, in step with every write; that digest is
#  how bck_loop compares facts. A write that bypasses them leaves the
#  digest stale: the loop can stop a walk early and miss what only a
#  later walk would find, such as a use-after-free on the second
#  iteration (agora #210, h118). So the only direct writes allowed are
#  the wrappers' own.
#
#  Usage:  tools/check_bck_writes.sh
#  Exit:   0 clean · 1 a direct write
# ============================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/compiler/nurlc.nu"

bad=$(awk '
    /^(unsafe )?@ / { fn = $0; sub(/^(unsafe )?@ /, "", fn); sub(/ .*/, "", fn) }
    /nurl_sym_(set|set_deep|def|append|append_word) g_bck[ )]/ {
        if (fn != "bck_put" && fn != "bck_add_word" && fn != "bck_add") printf "%s:%d (%s): %s\n", FILENAME, NR, fn, $0
    }' "$SRC")

if [ -n "$bad" ]; then
    echo "check_bck_writes: g_bck written directly, past the walk logs:"
    printf '%s\n' "$bad" | sed 's/^/    /'
    echo
    echo "  Write g_bck through bck_put (set), bck_add_word or bck_add (append)."
    echo "  bck_loop's fixpoint compares the facts in g_bck through a digest the"
    echo "  wrappers keep in step with every write (g_bck_dg); a direct write leaves"
    echo "  it stale and can end a loop's analysis before a later walk would have"
    echo "  found an error."
    exit 1
fi
echo "check_bck_writes: every g_bck write goes through bck_put / bck_add_word / bck_add"
