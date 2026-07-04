#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/lsp_rename_smoke.sh — end-to-end smoke test for
#  textDocument/rename in the nurl-lsp language server.
#
#  Drives build/nurl-lsp over stdio with Content-Length-framed
#  JSON-RPC (the LSP wire format) and asserts:
#
#    * initialize advertises "renameProvider":true;
#    * renaming a function used in two places returns a
#      WorkspaceEdit whose changes[] covers the declaration AND
#      both call sites (3 edits, each carrying the new name);
#    * an invalid newName (`9bad` — doesn't lex as an identifier)
#      is rejected with JSON-RPC error -32602, not a crash;
#    * a rename positioned on whitespace is rejected with -32602;
#    * a newName colliding with a type keyword (`String`) is
#      rejected with -32602;
#    * the server survives all of the above and answers shutdown.
#
#  Standalone script (same pattern as repl_smoke.sh) — not a golden
#  corpus entry. Run from anywhere; it cd's to the repo root.
#
#  Exit codes:
#    0 — all assertions passed
#    1 — assertion failure (server output printed)
#    2 — environment problem (could not build nurl-lsp)
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

LSP="$ROOT_DIR/build/nurl-lsp"
if [[ ! -x "$LSP" ]]; then
    echo "building nurl-lsp..." >&2
    if ! ./tools/nurl-lsp/build.sh >/dev/null 2>&1; then
        echo "ERROR: could not build build/nurl-lsp (run ./build.sh first)." >&2
        exit 2
    fi
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Sample workspace document: `helper` declared once (line 0, cols 2-8)
# and called twice from `main` (line 1).
SAMPLE_PATH="$TMPDIR/sample.nu"
cat > "$SAMPLE_PATH" <<'EOF'
@ helper i x → i { ^ + x 1 }
@ main → i { : i a ( helper 1 ) : i b ( helper 2 ) ^ + a b }
EOF
SAMPLE_URI="file://$SAMPLE_PATH"

# The same content as a JSON string body (\n-escaped, → passed through
# as raw UTF-8 — Content-Length below is computed in bytes).
DOC_TEXT='@ helper i x → i { ^ + x 1 }\n@ main → i { : i a ( helper 1 ) : i b ( helper 2 ) ^ + a b }\n'

# Emit one Content-Length-framed JSON-RPC message. Byte-accurate
# length via wc -c (the body contains multi-byte UTF-8 arrows).
frame() {
    local body="$1"
    local len
    len=$(printf '%s' "$body" | wc -c)
    printf 'Content-Length: %d\r\n\r\n%s' "$len" "$body"
}

REQS="$TMPDIR/requests.bin"
{
    frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"rootUri":"file://'"$TMPDIR"'","capabilities":{}}}'
    frame '{"jsonrpc":"2.0","method":"initialized","params":{}}'
    frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"'"$SAMPLE_URI"'","languageId":"nurl","version":1,"text":"'"$DOC_TEXT"'"}}}'
    # id 2: rename `helper` (cursor inside the decl name, line 0 char 3) → `stepper`.
    frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/rename","params":{"textDocument":{"uri":"'"$SAMPLE_URI"'"},"position":{"line":0,"character":3},"newName":"stepper"}}'
    # id 3: invalid newName (starts with a digit) → -32602.
    frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/rename","params":{"textDocument":{"uri":"'"$SAMPLE_URI"'"},"position":{"line":0,"character":3},"newName":"9bad"}}'
    # id 4: position on whitespace (line 0 char 1 is the space after `@`) → -32602.
    frame '{"jsonrpc":"2.0","id":4,"method":"textDocument/rename","params":{"textDocument":{"uri":"'"$SAMPLE_URI"'"},"position":{"line":0,"character":1},"newName":"fine_name"}}'
    # id 5: newName collides with a type keyword → -32602.
    frame '{"jsonrpc":"2.0","id":5,"method":"textDocument/rename","params":{"textDocument":{"uri":"'"$SAMPLE_URI"'"},"position":{"line":0,"character":3},"newName":"String"}}'
    frame '{"jsonrpc":"2.0","id":9,"method":"shutdown"}'
    frame '{"jsonrpc":"2.0","method":"exit"}'
} > "$REQS"

OUT="$TMPDIR/responses.txt"
"$LSP" < "$REQS" > "$OUT" 2>"$TMPDIR/stderr.txt"
RC=$?
if [[ $RC -ne 0 ]]; then
    echo "FAIL: server exited with code $RC (expected 0 after shutdown+exit)" >&2
    cat "$TMPDIR/stderr.txt" >&2
    exit 1
fi

# Split the framed output stream into one JSON body per line.
BODIES="$TMPDIR/bodies.txt"
tr -d '\r' < "$OUT" | sed 's/Content-Length:/\n&/g' | grep '^{' > "$BODIES"

fail() {
    echo "FAIL: $1" >&2
    echo "--- server bodies ---" >&2
    cat "$BODIES" >&2
    exit 1
}

# 1. initialize advertises renameProvider.
grep -q '"renameProvider":true' "$BODIES" \
    || fail "initialize result does not advertise renameProvider:true"

# 2. id 2 → WorkspaceEdit with 3 edits (decl + 2 refs), all newText=stepper.
R2=$(grep '"id":2' "$BODIES") || fail "no response for rename request id 2"
echo "$R2" | grep -q '"changes"' || fail "rename response lacks changes"
echo "$R2" | grep -q "$SAMPLE_URI" || fail "rename changes lack the document URI"
N_EDITS=$(echo "$R2" | grep -o '"newText":"stepper"' | wc -l)
[[ "$N_EDITS" -eq 3 ]] || fail "expected 3 stepper edits, got $N_EDITS: $R2"
# Declaration range: line 0, cols 2..8 (byte columns, `helper` is 6 long).
echo "$R2" | grep -q '{"line":0,"character":2},"end":{"line":0,"character":8}' \
    || fail "rename edits do not cover the declaration range 0:2-0:8: $R2"
# Both call-site edits land on line 1.
N_LINE1=$(echo "$R2" | grep -o '"line":1,' | wc -l)
[[ "$N_LINE1" -ge 4 ]] || fail "expected 2 call-site edits on line 1: $R2"

# 3. id 3 → -32602 (newName not an identifier).
R3=$(grep '"id":3' "$BODIES") || fail "no response for rename request id 3"
echo "$R3" | grep -q '"error"' || fail "invalid newName was not rejected: $R3"
echo "$R3" | grep -q '\-32602' || fail "invalid newName rejection is not -32602: $R3"

# 4. id 4 → -32602 (position on whitespace).
R4=$(grep '"id":4' "$BODIES") || fail "no response for rename request id 4"
echo "$R4" | grep -q '\-32602' || fail "whitespace-position rename not rejected with -32602: $R4"

# 5. id 5 → -32602 (newName is a reserved word).
R5=$(grep '"id":5' "$BODIES") || fail "no response for rename request id 5"
echo "$R5" | grep -q '\-32602' || fail "reserved-word newName not rejected with -32602: $R5"

echo "PASS lsp_rename_smoke"
exit 0
