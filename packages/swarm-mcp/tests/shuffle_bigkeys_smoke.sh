#!/usr/bin/env bash
# packages/swarm-mcp/tests/shuffle_bigkeys_smoke.sh — compute_shuffle at the
# lifted limits and its correctness guards:
#   A. LARGE INPUT — 10 M elements (over the old 8.4 M cap) with 100 keys. The
#      result is bounded by the distinct-key count, not the row count, so a
#      high-VOLUME group-by now works.
#   B. HIGH CARDINALITY — 200 000 distinct keys (over the old 65 536 cap): the
#      total scales with the chunk count, so it now works, returned via out_file
#      (raw i64 key / f64 value pairs); parsed back and verified.
#   C. OVERFLOW DETECTION — 500 000 keys forces a single chunk past its table
#      (~131072), which must ERROR (never silently drop keys / return wrong counts).
#
#   ./tests/shuffle_bigkeys_smoke.sh          # from the package root
# Skips (exit 0) without an NVIDIA GPU.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[bigkeys-smoke] SKIP — no NVIDIA GPU visible"; exit 0
fi

PORT="${SWARM_PORT:-47902}"; MCPP="${SWARM_MCP_PORT:-48465}"
TOKEN="bigkeys-smoke-secret"
TMP="$(mktemp -d)"; export HOME="$TMP"; export TMPDIR="$TMP"
BIN="$TMP/swarm-mcp"; WT="$TMP/wt"; node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
MCP() { curl -sk -m 200 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[bigkeys-smoke] building swarm-mcp + wasmtime"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[bigkeys-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/wasmtime/src/main.nu" "$WT" >/dev/null 2>&1 || { echo "[bigkeys-smoke] FAIL build wt"; exit 1; }

echo "[bigkeys-smoke] starting node on :$PORT / :$MCPP"
WASMTIME="$WT" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.log" 2>&1 &
node_pid=$!; sleep 2.5
fail=0

run_shuffle() {  # $1 = arguments-json
    local req res
    req="$(python3 -c "import json,sys; print(json.dumps({'jsonrpc':'2.0','id':1,'method':'tools/call','params':{'name':'compute_shuffle','arguments':json.loads(sys.argv[1])}}))" "$1")"
    res="$(MCP "$req")"
    printf '%s' "$res" | python3 -c "import json,sys
try:
    print(json.load(sys.stdin)['result']['content'][0]['text'])
except Exception as e: print('{\"error\":\"%s\"}' % e)"
}

# ── A. large input: key(x)=x%100 over [0,10000000) → 10 M > old 8.4 M cap ──
MAPC='__device__ long long key(long long x) { return x % 100; } __device__ double value(long long x) { return 1.0; }'
argsA="$(python3 -c "import json,sys; print(json.dumps({'map':sys.argv[1],'reduce':'count','lo':0,'hi':10000000}))" "$MAPC")"
rA="$(run_shuffle "$argsA")"
okA="$(printf '%s' "$rA" | python3 -c "import json,sys
try:
    o=json.load(sys.stdin); g=o.get('groups',{})
    print('OK' if o.get('n_groups')==100 and all(g.get(str(k))==100000 for k in range(100)) else 'BAD '+str(o)[:120])
except Exception as e: print('ERR '+str(e))" 2>/dev/null)"
if [ "$okA" = OK ]; then echo "[bigkeys-smoke] PASS A: 10 M elements (over the old 8.4 M cap), 100 keys × 100000"; else
    echo "[bigkeys-smoke] FAIL A: $okA — $(printf '%s' "$rA" | head -c 160)"; fail=1; fi

# ── B. high cardinality: key(x)=x over [0,200000) → 200000 keys (> old 65536) ──
OUT="$TMP/groups.bin"
MAPB='__device__ long long key(long long x) { return x; } __device__ double value(long long x) { return 1.0; }'
argsB="$(python3 -c "import json,sys; print(json.dumps({'map':sys.argv[1],'reduce':'count','lo':0,'hi':200000,'out_file':sys.argv[2]}))" "$MAPB" "$OUT")"
rB="$(run_shuffle "$argsB")"
ngB="$(printf '%s' "$rB" | python3 -c "import json,sys; print(json.load(sys.stdin).get('n_groups','?'))" 2>/dev/null)"
if [ "$ngB" = "200000" ] && [ -f "$OUT" ]; then
    okB="$(python3 -c "
import struct
data=open('$OUT','rb').read()
pairs=[struct.unpack('<qd', data[i:i+16]) for i in range(0,len(data),16)]
keys=set(k for k,_ in pairs); vals=[v for _,v in pairs]
print('OK' if len(pairs)==200000 and keys==set(range(200000)) and all(v==1.0 for v in vals) else 'BAD %d'%len(pairs))")"
    if [ "$okB" = OK ]; then echo "[bigkeys-smoke] PASS B: 200000 groups (over the old 65536 cap) via out_file, every count == 1"; else
        echo "[bigkeys-smoke] FAIL B: $okB"; fail=1; fi
else
    echo "[bigkeys-smoke] FAIL B: n_groups=$ngB (want 200000) — $(printf '%s' "$rB" | head -c 160)"; fail=1
fi

# ── C. overflow: key(x)=x over [0,500000) → ~250000 keys/chunk > table → ERROR ──
argsC="$(python3 -c "import json,sys; print(json.dumps({'map':sys.argv[1],'reduce':'count','lo':0,'hi':500000,'out_file':sys.argv[2]}))" "$MAPB" "$TMP/c.bin")"
rC="$(run_shuffle "$argsC")"
if printf '%s' "$rC" | grep -qiE 'overflow'; then
    echo "[bigkeys-smoke] PASS C: a chunk exceeding its table is rejected (no silent drop)"
else
    echo "[bigkeys-smoke] FAIL C: expected an overflow error, got: $(printf '%s' "$rC" | head -c 200)"; fail=1
fi

if [ "$fail" = 0 ]; then echo "[bigkeys-smoke] ALL PASS"; else echo "[bigkeys-smoke] FAILURES"; tail -15 "$TMP/node.log"; fi
exit $fail
