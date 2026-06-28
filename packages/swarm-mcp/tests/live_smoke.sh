#!/usr/bin/env bash
# packages/swarm-mcp/tests/live_smoke.sh — build swarm-mcp and exercise the full
# path: a relay + workers, a manual CLI submit, and an MCP session (initialize →
# tools/list → compute_submit → compute_result) over stdin JSON-RPC.
#
#   ./tests/live_smoke.sh
#
# Run from the package root. Loopback only; starts its own relay + workers.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

PORT="${SWARM_PORT:-47880}"
TMP="$(mktemp -d)"
BIN="$TMP/swarm-mcp"
pids=()
cleanup() { for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done; rm -rf "$TMP"; }
trap cleanup EXIT

echo "[smoke] building swarm-mcp"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1

echo "[smoke] starting relay + 3 workers on :$PORT"
"$BIN" relay 127.0.0.1 "$PORT" >"$TMP/relay.log" 2>&1 &
pids+=($!)
sleep 0.6
for i in 1 2 3; do
    "$BIN" worker 127.0.0.1 "$PORT" "$i" 0 >"$TMP/w$i.log" 2>&1 &
    pids+=($!)
done
sleep 1.0

fail=0

# 1. CLI submit: sum of x*x over [1,1000) = 332833500
out="$("$BIN" submit 127.0.0.1 "$PORT" sum 1 1000 'x*x' 2>&1 | tr -d '\n')"
if echo "$out" | grep -q "332833500"; then echo "[smoke] PASS cli sum x*x = 332833500"; else
    echo "[smoke] FAIL cli sum — got: $out"; fail=1; fi

# 2. MCP session: submit count of even numbers in [0,1000000) → 500000
mcp_out="$( {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"compute_submit","arguments":{"expr":"x%2==0","lo":0,"hi":1000000,"reduce":"count"}}}'
    sleep 2
    printf '%s\n' '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"compute_result","arguments":{"task_id":1}}}'
    sleep 1
} | "$BIN" mcp 127.0.0.1 "$PORT" 2>/dev/null )"

if echo "$mcp_out" | grep -q '"name":"compute_submit"'; then echo "[smoke] PASS mcp tools/list advertises compute_submit"; else
    echo "[smoke] FAIL mcp tools/list"; fail=1; fi
if echo "$mcp_out" | grep -q '500000'; then echo "[smoke] PASS mcp compute count = 500000"; else
    echo "[smoke] FAIL mcp compute — output:"; echo "$mcp_out" | sed 's/^/    /'; fail=1; fi

if [ "$fail" = 0 ]; then echo "[smoke] OK"; else echo "[smoke] FAILED"; exit 1; fi
