#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/repl_smoke.sh — end-to-end smoke test for the
#  `nurl repl` (tools/repl).
#
#  Drives a scripted session over a pipe (non-tty → the plain-read
#  fallback path) and asserts the cache of REPL behaviours that are
#  easy to get wrong:
#
#    * an eval line's output reaches stdout, REPL chrome does not
#      (prompts / acks / errors all go to stderr);
#    * a `@` function definition persists and is callable on a later
#      line (process-per-eval still shares the accumulated session);
#    * a `:` global persists and composes with a persisted function;
#    * a definition that fails the frontend check is rejected and does
#      NOT poison subsequent evaluations;
#    * `:quit` ends the loop cleanly.
#
#  Because every eval shells out to ./nurl.sh (nurlc + clang), this is
#  a heavier test than the .nu corpus — it is a standalone script, not
#  a golden-compared corpus entry. Run from anywhere; it cd's to root.
#
#  Exit codes:
#    0 — stdout matched expectation
#    1 — mismatch (full actual/expected diff printed)
#    2 — environment problem (could not build the repl)
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

REPL="$ROOT_DIR/build/nurl-repl"
if [[ ! -x "$REPL" ]]; then
    echo "building nurl-repl..." >&2
    if ! ./tools/repl/build.sh >/dev/null 2>&1; then
        echo "ERROR: could not build build/nurl-repl (run ./build.sh first)." >&2
        exit 2
    fi
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Scripted session. `oops` is undefined → that definition's USE must be
# rejected; the session keeps working afterward.
SESSION=$(cat <<'EOS'
( nurl_print `hi\n` )
@ sq i x → i { ^ * x x }
( nurl_print ( nurl_str_int ( sq 9 ) ) ) ( nurl_print `\n` )
: i base 100
( nurl_print ( nurl_str_int + base ( sq 3 ) ) ) ( nurl_print `\n` )
( nurl_print ( oops 1 ) )
( nurl_print ( nurl_str_int ( sq 4 ) ) ) ( nurl_print `\n` )
:quit
EOS
)

ACTUAL="$TMPDIR/out.txt"
printf '%s\n' "$SESSION" | "$REPL" >"$ACTUAL" 2>"$TMPDIR/err.txt"

EXPECT="$TMPDIR/expect.txt"
cat >"$EXPECT" <<'EOE'
hi
81
109
16
EOE

if cmp -s "$ACTUAL" "$EXPECT"; then
    echo "repl smoke: OK (definitions + globals persist, errors isolated, stdout clean)"
    exit 0
fi

echo "repl smoke: FAIL — stdout did not match"
echo "── expected ─────────────────────"
cat "$EXPECT"
echo "── actual ───────────────────────"
cat "$ACTUAL"
echo "── stderr (chrome + diagnostics) ─"
cat "$TMPDIR/err.txt"
exit 1
