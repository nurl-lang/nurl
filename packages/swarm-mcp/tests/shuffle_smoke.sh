#!/usr/bin/env bash
# packages/swarm-mcp/tests/shuffle_smoke.sh — the shuffle primitive live.
# Distributed map emits (key = x mod M, value = 1); compute_shuffle groups by
# key and counts. Over [0,N) each key 0..M-1 gets exactly N/M elements — an
# exact oracle. Also runs a group-SUM (value = x) and checks a couple keys.
#
#   ./tests/shuffle_smoke.sh          # from the package root
# Skips (exit 0) without an NVIDIA GPU. Needs curl + the build API.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"; export NURL_STDLIB="$REPO"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[shuffle-smoke] SKIP — no NVIDIA GPU visible"; exit 0
fi

PORT="${SWARM_PORT:-47914}"; MCPP="${SWARM_MCP_PORT:-48474}"
TOKEN="shuffle-smoke-secret"
TMP="$(mktemp -d)"; export HOME="$TMP"; export TMPDIR="$TMP"
BIN="$TMP/swarm-mcp"; WT="$TMP/wt"; node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
MCP() { curl -sk -m 180 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[shuffle-smoke] building"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[shuffle-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/wasmtime/src/main.nu" "$WT" >/dev/null 2>&1 || { echo "[shuffle-smoke] FAIL build wt"; exit 1; }

echo "[shuffle-smoke] starting node"
WASMTIME="$WT" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.log" 2>&1 &
node_pid=$!; sleep 2.5
fail=0

# group-by-count: key = x mod 10 over [0, 1_000_000) → each key = 100000
MAP='__device__ long long key(long long x) { return x % 10; } __device__ double value(long long x) { return 1.0; }'
req="$(python3 -c "import json,sys; print(json.dumps({'jsonrpc':'2.0','id':1,'method':'tools/call','params':{'name':'compute_shuffle','arguments':{'map':sys.argv[1],'reduce':'count','lo':0,'hi':300000}}}))" "$MAP")"
res="$(MCP "$req")"
echo "[shuffle-smoke] count result: $(printf '%s' "$res" | grep -oE '"text":"[^"]*"' | head -c 220)"
ok="$(printf '%s' "$res" | python3 -c "
import json,sys
d=json.load(sys.stdin); t=json.loads(d['result']['content'][0]['text'])
g=t['groups']; exp={str(k):30000.0 for k in range(10)}
print('OK' if t['n_groups']==10 and all(abs(g.get(str(k),-1)-30000.0)<0.5 for k in range(10)) else 'BAD:'+str(t))
" 2>/dev/null)"
if [ "$ok" = OK ]; then echo "[shuffle-smoke] PASS group-by-count: 10 keys x 30000 each"; else
    echo "[shuffle-smoke] FAIL count: $ok"; fail=1; fi

# group-by-sum: key = x mod 3, value = x over [0, 30) → sums 135,145,155
MAP2='__device__ long long key(long long x) { return x % 3; } __device__ double value(long long x) { return (double)x; }'
req2="$(python3 -c "import json,sys; print(json.dumps({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'compute_shuffle','arguments':{'map':sys.argv[1],'reduce':'sum','lo':0,'hi':30}}}))" "$MAP2")"
res2="$(MCP "$req2")"
ok2="$(printf '%s' "$res2" | python3 -c "
import json,sys
d=json.load(sys.stdin); t=json.loads(d['result']['content'][0]['text']); g=t['groups']
exp={}
for x in range(30): exp[str(x%3)]=exp.get(str(x%3),0)+x
print('OK' if all(abs(g.get(k,-1)-v)<0.5 for k,v in exp.items()) else 'BAD:'+str(g)+' exp '+str(exp))
" 2>/dev/null)"
if [ "$ok2" = OK ]; then echo "[shuffle-smoke] PASS group-by-sum: per-key sums match"; else
    echo "[shuffle-smoke] FAIL sum: $ok2"; fail=1; fi

if [ "$fail" = 0 ]; then echo "[shuffle-smoke] ALL PASS"; else echo "[shuffle-smoke] FAILURES"; tail -15 "$TMP/node.log"; fi
exit $fail
