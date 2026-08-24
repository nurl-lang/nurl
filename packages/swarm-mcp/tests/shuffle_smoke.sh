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
BIN="$TMP/swarm-mcp"; NWASM="$TMP/nwasm"; node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
MCP() { curl -sk -m 180 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[shuffle-smoke] building"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[shuffle-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/nwasm/src/main.nu" "$NWASM" >/dev/null 2>&1 || { echo "[shuffle-smoke] FAIL build nwasm"; exit 1; }

echo "[shuffle-smoke] starting node"
NURL_WASM_RUNTIME="$NWASM" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
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

# group-by-max and group-by-min: key = x mod 4, value = x over [0, 100).
# Per key k, values are k, k+4, k+8, … so min = k, max = the largest ≤ 99.
MAP3='__device__ long long key(long long x) { return x % 4; } __device__ double value(long long x) { return (double)x; }'
for OP in max min; do
    req3="$(python3 -c "import json,sys; print(json.dumps({'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':'compute_shuffle','arguments':{'map':sys.argv[1],'reduce':sys.argv[2],'lo':0,'hi':100}}}))" "$MAP3" "$OP")"
    res3="$(MCP "$req3")"
    ok3="$(printf '%s' "$res3" | OP="$OP" python3 -c "
import json,sys,os
op=os.environ['OP']
d=json.load(sys.stdin); t=json.loads(d['result']['content'][0]['text']); g=t['groups']
exp={}
for x in range(100):
    k=str(x%4)
    exp[k]=x if k not in exp else (max(exp[k],x) if op=='max' else min(exp[k],x))
dist=t.get('distributed_reduce') is True
print('OK' if dist and all(abs(g.get(k,-1)-v)<0.5 for k,v in exp.items()) else 'BAD:'+str(g)+' exp '+str(exp)+' dist='+str(dist))
" 2>/dev/null)"
    if [ "$ok3" = OK ]; then echo "[shuffle-smoke] PASS group-by-$OP: per-key $OP match (+distributed flag)"; else
        echo "[shuffle-smoke] FAIL $OP: $ok3"; fail=1; fi
done

# multi-chunk merge stress: 1000 distinct keys over a large range forces every
# chunk to build a partial table that the coordinator must MERGE by key. Each
# key k in [0,1000) occurs 500 times over [0, 500000) → count 500.
MAP4='__device__ long long key(long long x) { return x % 1000; } __device__ double value(long long x) { return 1.0; }'
req4="$(python3 -c "import json,sys; print(json.dumps({'jsonrpc':'2.0','id':4,'method':'tools/call','params':{'name':'compute_shuffle','arguments':{'map':sys.argv[1],'reduce':'count','lo':0,'hi':500000}}}))" "$MAP4")"
res4="$(MCP "$req4")"
ok4="$(printf '%s' "$res4" | python3 -c "
import json,sys
d=json.load(sys.stdin); t=json.loads(d['result']['content'][0]['text']); g=t['groups']
print('OK' if t['n_groups']==1000 and all(abs(g.get(str(k),-1)-500.0)<0.5 for k in range(1000)) else 'BAD:n='+str(t.get('n_groups')))
" 2>/dev/null)"
if [ "$ok4" = OK ]; then echo "[shuffle-smoke] PASS multi-chunk merge: 1000 keys x 500 each"; else
    echo "[shuffle-smoke] FAIL merge: $ok4"; fail=1; fi

if [ "$fail" = 0 ]; then echo "[shuffle-smoke] ALL PASS"; else echo "[shuffle-smoke] FAILURES"; tail -15 "$TMP/node.log"; fi
exit $fail
