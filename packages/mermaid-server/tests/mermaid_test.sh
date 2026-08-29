#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/mermaid_test.sh — the package's full test suite:
#    1. unit suite  : parser, templates, layout, renderer, MCP dispatch
#    2. CLI         : render from stdin / from a file / to -o, templates,
#                     --template, exit codes, error text
#    3. live HTTP   : the server over curl — /healthz, /templates, /render
#                     (GET + POST), /render.json, /, and MCP at /mcp
#
#  Run from the package dir:  ./tests/mermaid_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
#       PORT (default 8817)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

PORT="${PORT:-8817}"
WORK="$(mktemp -d -t mermaid-test.XXXXXX)"
SERVE_PID=""
cleanup() { [ -n "$SERVE_PID" ] && kill "$SERVE_PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }
has()   { case "$2" in *"$3"*) ok "$1";; *) bad "$1 (missing '$3')";; esac; }

echo "[1/3] unit suite"
if ! $NURL tests/mermaid_test.nu "$WORK/unit" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build tests/mermaid_test.nu:"; tail -5 "$WORK/build.err"; exit 1
fi
if "$WORK/unit" > "$WORK/unit.out" 2>&1; then
    ok "mermaid_test.nu ($(tail -1 "$WORK/unit.out"))"
else
    bad "mermaid_test.nu"; grep FAIL "$WORK/unit.out" | head -10
fi

echo "[2/3] CLI"
if ! $NURL src/main.nu "$WORK/mermaid-server" >/dev/null 2>"$WORK/build2.err"; then
    echo "FAIL: could not build src/main.nu:"; tail -5 "$WORK/build2.err"; exit 1
fi
BIN="$WORK/mermaid-server"

printf 'graph TD\n  A[Start] --> B{Ok?}\n  B -->|yes| C([Done])\n' > "$WORK/d.mmd"

OUT=$(printf 'graph TD\n  A --> B\n' | "$BIN" render 2>/dev/null)
has "render reads stdin" "$OUT" "<svg xmlns="
OUT=$("$BIN" render "$WORK/d.mmd" 2>/dev/null)
has "render reads a file" "$OUT" "data-id=\"B\""
"$BIN" render "$WORK/d.mmd" -o "$WORK/d.svg" >/dev/null 2>&1
check "render -o writes a file" "$([ -s "$WORK/d.svg" ] && echo yes)" "yes"
OUT=$("$BIN" render -t dark "$WORK/d.mmd" 2>/dev/null)
has "render -t picks a template" "$OUT" "#0b1120"
OUT=$("$BIN" templates 2>/dev/null)
has "templates lists dark" "$OUT" "dark"
has "templates marks the default" "$OUT" "(default)"

printf 'graph TD\n  A[oops\n' | "$BIN" render >/dev/null 2>"$WORK/err.txt"
check "a parse error exits non-zero" "$?" "1"
has "the parse error names a line" "$(cat "$WORK/err.txt")" "line 2"

printf 'graph TD\n  A --> B\n' | "$BIN" render -t nope >/dev/null 2>"$WORK/err2.txt"
has "an unknown template is reported" "$(cat "$WORK/err2.txt")" "unknown template"

MERMAID_TEMPLATES="$WORK/none" "$BIN" templates >/dev/null 2>"$WORK/err3.txt"
check "a missing template dir exits non-zero" "$?" "1"
has "and says which directory" "$(cat "$WORK/err3.txt")" "$WORK/none"

echo "[3/3] live HTTP + MCP"
"$BIN" --port "$PORT" --workers 2 --quiet >"$WORK/serve.log" 2>&1 &
SERVE_PID=$!
for _ in $(seq 60); do
    curl -s -m 1 "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 && break
    sleep 0.1 2>/dev/null || true
done

check "GET /healthz" "$(curl -s -m 5 "http://127.0.0.1:$PORT/healthz")" "ok"
has "GET /templates" "$(curl -s -m 5 "http://127.0.0.1:$PORT/templates")" '"default":"default"'
has "GET / serves the playground" "$(curl -s -m 5 "http://127.0.0.1:$PORT/")" "<title>mermaid-server</title>"

CT=$(curl -s -m 5 -o "$WORK/r.svg" -w '%{content_type}' -X POST --data-binary @"$WORK/d.mmd" "http://127.0.0.1:$PORT/render")
check "POST /render content type" "$CT" "image/svg+xml; charset=utf-8"
has "POST /render body" "$(cat "$WORK/r.svg")" "<svg xmlns="

CODE=$(curl -s -m 5 -o "$WORK/g.svg" -w '%{http_code}' "http://127.0.0.1:$PORT/render?src=graph%20LR%0AA%5BHi%5D%20--%3E%20B")
check "GET /render?src=" "$CODE" "200"
has "GET /render body" "$(cat "$WORK/g.svg")" "data-id=\"A\""

has "POST /render.json" "$(curl -s -m 5 -X POST --data-binary @"$WORK/d.mmd" "http://127.0.0.1:$PORT/render.json")" '"nodes":3'
has "?template= reaches the renderer" \
    "$(curl -s -m 5 -X POST --data-binary @"$WORK/d.mmd" "http://127.0.0.1:$PORT/render.json?template=blueprint")" "#0f3d6e"
has "X-Template header reaches it too" \
    "$(curl -s -m 5 -X POST -H 'X-Template: dark' --data-binary @"$WORK/d.mmd" "http://127.0.0.1:$PORT/render.json")" "#0b1120"

CODE=$(curl -s -m 5 -o "$WORK/e.json" -w '%{http_code}' -X POST --data-binary $'graph TD\n A[oops\n' "http://127.0.0.1:$PORT/render.json")
check "a parse error is a 400" "$CODE" "400"
has "with the line and column" "$(cat "$WORK/e.json")" '"line":2'

has "a warning rides a response header" \
    "$(curl -s -m 5 -D- -o /dev/null -X POST --data-binary $'graph TD\n classDef x fill:#fff\n A-->B\n' "http://127.0.0.1:$PORT/render")" \
    "X-Mermaid-Warnings:"

MCP='{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
has "MCP tools/list" "$(curl -s -m 5 -X POST -H 'Content-Type: application/json' --data "$MCP" "http://127.0.0.1:$PORT/mcp")" "mermaid_render"
MCP='{"jsonrpc":"2.0","id":2,"method":"initialize","params":{}}'
has "MCP initialize" "$(curl -s -m 5 -X POST -H 'Content-Type: application/json' --data "$MCP" "http://127.0.0.1:$PORT/mcp")" "mermaid-server"
MCP='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"mermaid_render","arguments":{"source":"graph TD\n A-->B\n","template":"dark"}}}'
has "MCP tools/call renders" "$(curl -s -m 5 -X POST -H 'Content-Type: application/json' --data "$MCP" "http://127.0.0.1:$PORT/mcp")" "<svg xmlns="
MCP='{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"mermaid_validate","arguments":{"source":"graph TD\n A-->B\n"}}}'
has "MCP tools/call validates" "$(curl -s -m 5 -X POST -H 'Content-Type: application/json' --data "$MCP" "http://127.0.0.1:$PORT/mcp")" "ok: 2 nodes"

# The stdio transport speaks the same dispatcher.
OUT=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | "$BIN" --stdio 2>/dev/null)
has "MCP over --stdio" "$OUT" "mermaid_templates"

echo
echo "mermaid-server: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
