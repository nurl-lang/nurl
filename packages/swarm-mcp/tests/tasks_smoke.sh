#!/usr/bin/env bash
# packages/swarm-mcp/tests/tasks_smoke.sh — live end-to-end for the MCP
# `io.modelcontextprotocol/tasks` extension over the real HTTPS JSON-RPC
# transport.
#
# The compute_submit family already behaved like a task API through its own
# tool arguments (submit → task_id → compute_result). This checks the same
# work driven through the PROTOCOL instead: a task-declaring client gets a
# CreateTaskResult and polls tasks/get.
#
# Covered:
#   1. server/discover advertises capabilities.extensions[io.…/tasks]
#   2. a client that does NOT declare the extension gets the old CallToolResult
#      (the spec forbids handing it a CreateTaskResult)
#   3. a declaring client gets resultType "task" + a 32-hex taskId
#   4. tasks/get polls to "completed" and inlines the real tool result
#   5. a completed task stays re-pollable (the result is not consumed)
#   6. tasks/get without the capability → -32003
#   7. an unknown taskId → -32602
#   8. tasks/cancel acks (cooperative — it does not force the status)
#   9. a non-eligible tool is never augmented, even for a declaring client
#
#   ./tests/tasks_smoke.sh          # from the package root
# Loopback only; starts its own node. Needs curl. CPU only — no GPU required.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

PORT="${SWARM_PORT:-47882}"
MCPP="${SWARM_MCP_PORT:-48445}"
TOKEN="tasks-smoke-secret"
TMP="$(mktemp -d)"
export HOME="$TMP"          # isolate the auto-generated TLS cert under $TMP
BIN="$TMP/swarm-mcp"
node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -TERM "$node_pid" 2>/dev/null; sleep 0.3; [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

MCP() { curl -sk -m 20 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

# The per-request `_meta` a tasks-capable client sends. Modern-era clients
# declare their capabilities on every request, not once at handshake.
CAPS='"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{"extensions":{"io.modelcontextprotocol/tasks":{}}}}'

echo "[tasks-smoke] building swarm-mcp"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[tasks-smoke] FAIL build"; exit 1; }

echo "[tasks-smoke] starting all-in-one node (relay + 3 workers + mcp/HTTPS) on :$PORT / :$MCPP"
"$BIN" --token "$TOKEN" --relay --worker --workers 3 --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.log" 2>&1 &
node_pid=$!
sleep 2.5

fail=0

# 1. server/discover declares the extension.
disc="$(MCP '{"jsonrpc":"2.0","id":1,"method":"server/discover"}')"
if printf '%s' "$disc" | grep -q '"extensions":{"io.modelcontextprotocol/tasks":{}}'; then
    echo "[tasks-smoke] PASS discover declares io.modelcontextprotocol/tasks"
else
    echo "[tasks-smoke] FAIL discover — got: $disc"; fail=1
fi

# 2. A NON-declaring client must still get the plain CallToolResult. Task
#    creation is server-directed, but the spec forbids returning one to a
#    client that did not declare the extension on the request.
plain="$(MCP '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"compute_submit","arguments":{"expr":"x","lo":0,"hi":1000,"reduce":"sum"}}}')"
if printf '%s' "$plain" | grep -q '"resultType":"task"'; then
    echo "[tasks-smoke] FAIL non-declaring client got a CreateTaskResult"; fail=1
elif printf '%s' "$plain" | grep -q 'task_id'; then
    echo "[tasks-smoke] PASS non-declaring client gets the plain tool result"
else
    echo "[tasks-smoke] FAIL non-declaring submit — got: $plain"; fail=1
fi

# 3. A DECLARING client gets a CreateTaskResult. Σ x over [0,1000) = 499500.
sub="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_submit\",\"arguments\":{\"expr\":\"x\",\"lo\":0,\"hi\":1000,\"reduce\":\"sum\"},$CAPS}}")"
if printf '%s' "$sub" | grep -q '"resultType":"task"'; then
    echo "[tasks-smoke] PASS tools/call → CreateTaskResult"
else
    echo "[tasks-smoke] FAIL no CreateTaskResult — got: $sub"; fail=1
fi
TID="$(printf '%s' "$sub" | grep -oE '"taskId":"[0-9a-f]+"' | grep -oE '[0-9a-f]{8,}' | head -1)"
if [ "${#TID}" = 32 ]; then
    echo "[tasks-smoke] PASS taskId is 32 hex chars"
else
    echo "[tasks-smoke] FAIL taskId shape — got: '$TID'"; fail=1
fi
# The seed state must carry the polling contract the client needs.
if printf '%s' "$sub" | grep -q '"ttlMs":' && printf '%s' "$sub" | grep -q '"pollIntervalMs":' \
   && printf '%s' "$sub" | grep -q '"createdAt":' && printf '%s' "$sub" | grep -q '"lastUpdatedAt":'; then
    echo "[tasks-smoke] PASS CreateTaskResult carries ttlMs/pollIntervalMs/timestamps"
else
    echo "[tasks-smoke] FAIL CreateTaskResult fields — got: $sub"; fail=1
fi
[ -z "$TID" ] && { echo "[tasks-smoke] cannot continue without a taskId"; exit 1; }

# 4. Poll tasks/get until the task completes, then read the inlined result.
GET() { MCP "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tasks/get\",\"params\":{\"taskId\":\"$1\",$CAPS}}"; }
ok=0; got=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    got="$(GET "$TID")"
    if printf '%s' "$got" | grep -q '"status":"completed"'; then ok=1; break; fi
    sleep 0.7
done
if [ "$ok" = 1 ]; then
    echo "[tasks-smoke] PASS tasks/get reaches completed"
else
    echo "[tasks-smoke] FAIL tasks/get never completed — last: $got"; fail=1
fi
# tasks/get is itself an ordinary request, so its own result is "complete".
if printf '%s' "$got" | grep -q '"resultType":"complete"'; then
    echo "[tasks-smoke] PASS tasks/get result is resultType complete"
else
    echo "[tasks-smoke] FAIL tasks/get resultType — got: $got"; fail=1
fi
# The completed task inlines exactly what compute_result would have returned.
if printf '%s' "$got" | grep -q '499500'; then
    echo "[tasks-smoke] PASS completed task inlines the real result (Σx = 499500)"
else
    echo "[tasks-smoke] FAIL result payload — got: $got"; fail=1
fi

# 5. A completed task stays readable — the stored result is cloned per poll,
#    not moved out. A client that crashed mid-poll can come back for it.
again="$(GET "$TID")"
if printf '%s' "$again" | grep -q '499500'; then
    echo "[tasks-smoke] PASS completed task is re-pollable"
else
    echo "[tasks-smoke] FAIL re-poll — got: $again"; fail=1
fi

# 6. tasks/get WITHOUT the capability → -32003 naming the missing extension.
nocap="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tasks/get\",\"params\":{\"taskId\":\"$TID\"}}")"
if printf '%s' "$nocap" | grep -q '"code":-32003' \
   && printf '%s' "$nocap" | grep -q 'requiredCapabilities'; then
    echo "[tasks-smoke] PASS non-declaring tasks/get → -32003 + requiredCapabilities"
else
    echo "[tasks-smoke] FAIL capability gate — got: $nocap"; fail=1
fi

# 7. Unknown taskId → -32602 (Invalid params), never a bare result.
bogus="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tasks/get\",\"params\":{\"taskId\":\"00000000000000000000000000000000\",$CAPS}}")"
if printf '%s' "$bogus" | grep -q '"code":-32602'; then
    echo "[tasks-smoke] PASS unknown taskId → -32602"
else
    echo "[tasks-smoke] FAIL unknown taskId — got: $bogus"; fail=1
fi

# 8. tasks/cancel acks. Cancellation is cooperative: the ack is required, a
#    transition to "cancelled" is not — this task has already completed.
canc="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tasks/cancel\",\"params\":{\"taskId\":\"$TID\",$CAPS}}")"
if printf '%s' "$canc" | grep -q '"resultType":"complete"' && ! printf '%s' "$canc" | grep -q '"error"'; then
    echo "[tasks-smoke] PASS tasks/cancel acks"
else
    echo "[tasks-smoke] FAIL tasks/cancel — got: $canc"; fail=1
fi

# 9. A tool with no pollable handle is never augmented, capability or not.
help="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"swarm_help\",\"arguments\":{},$CAPS}}")"
if printf '%s' "$help" | grep -q '"resultType":"task"'; then
    echo "[tasks-smoke] FAIL swarm_help was augmented into a task"; fail=1
elif printf '%s' "$help" | grep -q '"content"'; then
    echo "[tasks-smoke] PASS non-eligible tool returns a plain result"
else
    echo "[tasks-smoke] FAIL swarm_help — got: $help"; fail=1
fi

# 10. An immediate tool ERROR is not a task either — there is nothing to poll.
#     An empty range is rejected before anything is submitted to the cluster.
badrange="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_submit\",\"arguments\":{\"expr\":\"x\",\"lo\":10,\"hi\":10},$CAPS}}")"
if printf '%s' "$badrange" | grep -q '"resultType":"task"'; then
    echo "[tasks-smoke] FAIL an immediate tool error was augmented into a task"; fail=1
elif printf '%s' "$badrange" | grep -q 'empty range'; then
    echo "[tasks-smoke] PASS immediate tool error stays a plain result"
else
    echo "[tasks-smoke] FAIL bad range — got: $badrange"; fail=1
fi

if [ "$fail" = 0 ]; then echo "[tasks-smoke] OK"; else echo "[tasks-smoke] FAILURES"; fi
exit "$fail"
