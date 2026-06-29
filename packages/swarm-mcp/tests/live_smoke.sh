#!/usr/bin/env bash
# packages/swarm-mcp/tests/live_smoke.sh — build swarm-mcp and exercise the full
# unified node: a single all-in-one process (--relay --worker --mcp) driven over
# HTTPS JSON-RPC (initialize → tools/list → compute_submit → compute_result),
# plus the dev CLI submit and token-isolation.
#
#   ./tests/live_smoke.sh
#
# Run from the package root. Loopback only; starts its own node.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

PORT="${SWARM_PORT:-47880}"
MCPP="${SWARM_MCP_PORT:-48443}"
TOKEN="smoke-secret"
TMP="$(mktemp -d)"
export HOME="$TMP"          # isolate the auto-generated TLS cert under $TMP
BIN="$TMP/swarm-mcp"
node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -TERM "$node_pid" 2>/dev/null; sleep 0.3; [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

MCP() { curl -sk -m 10 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[smoke] building swarm-mcp"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[smoke] FAIL build"; exit 1; }

echo "[smoke] starting all-in-one node (relay + 3 workers + mcp/HTTPS) on :$PORT / :$MCPP"
"$BIN" --token "$TOKEN" --relay --worker --workers 3 --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.log" 2>&1 &
node_pid=$!
sleep 2.5

fail=0

# 1. MCP initialize over HTTPS
if MCP '{"jsonrpc":"2.0","id":1,"method":"initialize"}' | grep -q '"serverInfo"'; then
    echo "[smoke] PASS mcp initialize (HTTPS)"; else echo "[smoke] FAIL mcp initialize"; fail=1; fi

# 2. tools/list advertises the surface
if MCP '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | grep -q '"name":"compute_submit"'; then
    echo "[smoke] PASS mcp tools/list"; else echo "[smoke] FAIL mcp tools/list"; fail=1; fi

# 3. compute_submit: count even numbers in [0,1000000) → 500000
sub="$(MCP '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"compute_submit","arguments":{"expr":"x%2==0","lo":0,"hi":1000000,"reduce":"count"}}}')"
tid="$(printf '%s' "$sub" | grep -oE 'task_id..[0-9]+' | grep -oE '[0-9]+' | head -1)"
[ -z "$tid" ] && tid=1
ok=0
for _ in 1 2 3 4 5 6 7 8; do
    res="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$tid}}}")"
    if printf '%s' "$res" | grep -q '500000'; then ok=1; break; fi
    sleep 0.7
done
if [ "$ok" = 1 ]; then echo "[smoke] PASS mcp compute count even = 500000"; else
    echo "[smoke] FAIL mcp compute — last: $res"; fail=1; fi

# 4. dev CLI submit: sum of x*x over [1,1000) = 332833500
cli="$("$BIN" submit 127.0.0.1 "$PORT" sum 1 1000 'x*x' --token "$TOKEN" 2>&1 | tr -d '\n')"
if printf '%s' "$cli" | grep -q '332833500'; then echo "[smoke] PASS cli submit x*x = 332833500"; else
    echo "[smoke] FAIL cli submit — got: $cli"; fail=1; fi

# 5. token isolation: the WRONG token sees no cluster
wrong="$("$BIN" submit 127.0.0.1 "$PORT" sum 1 1000 'x*x' --token nope 2>&1 | tr -d '\n')"
if printf '%s' "$wrong" | grep -q 'no workers'; then echo "[smoke] PASS token isolation (wrong token → no workers)"; else
    echo "[smoke] FAIL token isolation — got: $wrong"; fail=1; fi

if [ "$fail" = 0 ]; then echo "[smoke] OK"; else echo "[smoke] FAILED"; exit 1; fi
