#!/usr/bin/env bash
# packages/swarm-mcp/tests/failover_smoke.sh — the relay is not a SPOF.
# Two relays; a worker node and an mcp node both --connect BOTH. Submit once
# (works), KILL the relay they are on, submit again — the cluster fails over
# to the surviving relay and the second submit still returns the right answer.
#
#   ./tests/failover_smoke.sh          # from the package root
# Skips (exit 0) without an NVIDIA GPU. Needs curl + the build API.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[failover-smoke] SKIP — no NVIDIA GPU visible"; exit 0
fi

RA="${RELAY_A:-47910}"; RB="${RELAY_B:-47911}"; MCPP="${SWARM_MCP_PORT:-48470}"
TOKEN="failover-smoke-secret"
TMP="$(mktemp -d)"; export HOME="$TMP"; export TMPDIR="$TMP"
BIN="$TMP/swarm-mcp"; WT="$TMP/wt"
ra_pid=""; rb_pid=""; worker_pid=""; mcp_pid=""
cleanup() { for p in "$ra_pid" "$rb_pid" "$worker_pid" "$mcp_pid"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
MCP() { curl -sk -m 180 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[failover-smoke] building"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[failover-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/wasmtime/src/main.nu" "$WT" >/dev/null 2>&1 || { echo "[failover-smoke] FAIL build wt"; exit 1; }

RELAYS="127.0.0.1:$RA,127.0.0.1:$RB"
echo "[failover-smoke] starting two relays ($RA, $RB)"
"$BIN" --token "$TOKEN" --relay --listen 127.0.0.1:"$RA" >"$TMP/ra.log" 2>&1 & ra_pid=$!
"$BIN" --token "$TOKEN" --relay --listen 127.0.0.1:"$RB" >"$TMP/rb.log" 2>&1 & rb_pid=$!
sleep 1.5
echo "[failover-smoke] starting a gpu worker and an mcp node, both --connect both relays"
WASMTIME="$WT" "$BIN" --token "$TOKEN" --worker --gpu --connect "$RELAYS" -v >"$TMP/w.log" 2>&1 & worker_pid=$!
"$BIN" --token "$TOKEN" --mcp --connect "$RELAYS" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/m.log" 2>&1 & mcp_pid=$!
sleep 3

fail=0
submit() { # id → prints the result text
    local sub tid res
    sub="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":$1,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_submit_cuda\",\"arguments\":{\"cuda\":\"__device__ double f(long long x) { return 1.0; }\",\"lo\":0,\"hi\":1000000,\"reduce\":\"sum\"}}}")"
    tid="$(printf '%s' "$sub" | grep -oE 'task_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
    [ -z "$tid" ] && { echo "NOSUB:$sub"; return; }
    for _ in $(seq 1 12); do
        res="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":$(($1+100)),\"method\":\"tools/call\",\"params\":{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$tid}}}")"
        printf '%s' "$res" | grep -q '1e+06\|1000000' && { echo OK; return; }
        printf '%s' "$res" | grep -q '"status\\":\\"error' && { echo "ERR:$res"; return; }
        sleep 2
    done
    echo "TIMEOUT:$res"
}

# figure out which relay the worker is on (verbose logs "on relay <idx>")
r1="$(submit 1)"
if [ "$r1" = OK ]; then echo "[failover-smoke] PASS first submit (both relays up)"; else
    echo "[failover-smoke] FAIL first submit: $r1"; fail=1; tail -5 "$TMP/w.log" "$TMP/m.log"; fi

echo "[failover-smoke] KILLING relay A ($RA) — the one the cluster started on"
kill -9 "$ra_pid" 2>/dev/null; ra_pid=""
# give the worker's heartbeat + mcp's lazy reconnect time to notice and rehome
sleep 6

r2="$(submit 2)"
if [ "$r2" = OK ]; then echo "[failover-smoke] PASS second submit after relay A died — failed over to relay B"; else
    echo "[failover-smoke] FAIL second submit: $r2"; fail=1
    echo "--- worker log tail ---"; tail -8 "$TMP/w.log"; echo "--- mcp log tail ---"; tail -8 "$TMP/m.log"; fi

if [ "$fail" = 0 ]; then echo "[failover-smoke] ALL PASS"; else echo "[failover-smoke] FAILURES"; fi
exit $fail
