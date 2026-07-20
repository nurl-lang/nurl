#!/usr/bin/env bash
# packages/swarm-mcp/tests/general_smoke.sh — live end-to-end for the GENERAL
# iteration engine: an algorithm the built-in SGD step CANNOT express.
#
# 1D k-means (K=2, Lloyd) run entirely in the engine via compute_iterate with a
# custom "update" device function. It exercises the two things the SGD path
# forbids: the accumulator dimension (A=4: two sums + two counts) is WIDER than
# the state (S=2 centroids), and the step rule is centroid = sum/count, not
# theta -= lr*grad/N. The result must match a faithful numpy Lloyd oracle run
# over the identical data bytes with the identical init.
#
#   ./tests/general_smoke.sh          # from the package root
# Skips (exit 0) without an NVIDIA GPU. Needs curl + python3.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[general-smoke] SKIP — no NVIDIA GPU visible"; exit 0
fi

PORT="${SWARM_PORT:-47896}"; MCPP="${SWARM_MCP_PORT:-48459}"
TOKEN="general-smoke-secret"
TMP="$(mktemp -d)"; export HOME="$TMP"; export TMPDIR="$TMP"
BIN="$TMP/swarm-mcp"; WT="$TMP/wt"; node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -TERM "$node_pid" 2>/dev/null; sleep 0.3; [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
MCP() { curl -sk -m 180 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[general-smoke] building swarm-mcp + wasmtime"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[general-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/wasmtime/src/main.nu" "$WT" >/dev/null 2>&1 || { echo "[general-smoke] FAIL build wt"; exit 1; }

# Deterministic two-cluster data + the numpy Lloyd oracle over the SAME bytes.
INIT0=0.0; INIT1=50.0; ROUNDS=25
python3 - "$TMP/km.f64" "$INIT0" "$INIT1" "$ROUNDS" "$TMP/oracle.txt" <<'PY'
import struct, sys
path, c0, c1, rounds, opath = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
# 100k points: one cluster ~10, one ~100, deterministic ramps (no RNG mismatch)
pts = []
for k in range(50000): pts.append(10.0 + (k % 17) * 0.01)
for k in range(50000): pts.append(100.0 + (k % 23) * 0.01)
with open(path, "wb") as f:
    for v in pts: f.write(struct.pack("<d", v))
# faithful Lloyd: nearest by |v-c|, tie -> cluster 0; empty cluster keeps centroid
def lloyd(c0, c1, rounds):
    for _ in range(rounds):
        s0=s1=0.0; n0=n1=0
        for v in pts:
            if abs(v-c0) <= abs(v-c1): s0+=v; n0+=1
            else: s1+=v; n1+=1
        c0 = s0/n0 if n0>0 else c0
        c1 = s1/n1 if n1>0 else c1
    return c0, c1
o0, o1 = lloyd(c0, c1, rounds)
open(opath, "w").write("%.6f %.6f" % (o0, o1))
print("%.6f %.6f" % (o0, o1))
PY
read -r O0 O1 < "$TMP/oracle.txt"
echo "[general-smoke] numpy Lloyd oracle: c0=$O0 c1=$O1"

echo "[general-smoke] starting node on :$PORT / :$MCPP"
WASMTIME="$WT" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.log" 2>&1 &
node_pid=$!; sleep 2.5
fail=0

ds="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_upload_data\",\"arguments\":{\"file\":\"$TMP/km.f64\"}}}" | grep -oE 'dataset_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
[ -z "$ds" ] && { echo "[general-smoke] FAIL upload"; exit 1; }

# grad: assign each point to its nearest centroid, scatter (sum, count) into a
# 4-wide accumulator [sum0, sum1, count0, count1]. update: centroid = sum/count.
GRAD='__device__ void grad(long long x, double v, double* g, const double* p) { double d0 = v - p[0]; if (d0 < 0) d0 = -d0; double d1 = v - p[1]; if (d1 < 0) d1 = -d1; long long c = (d0 <= d1) ? 0 : 1; swarm_g_add(g, c, v); swarm_g_add(g, 2 + c, 1.0); }'
UPDATE='__device__ double update(long long j, const double* p) { double sum = swarm_acc(j); double cnt = swarm_acc(swarm_dim + j); return (cnt > 0.0) ? (sum / cnt) : swarm_state(j); }'

req="$(python3 -c "import json,sys; print(json.dumps({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'compute_iterate','arguments':{'cuda':sys.argv[1],'update':sys.argv[2],'state':[$INIT0,$INIT1],'acc_dim':4,'rounds':$ROUNDS,'epsilon':1e-6,'dataset':int(sys.argv[3])}}}))" "$GRAD" "$UPDATE" "$ds")"
res="$(MCP "$req")"
echo "[general-smoke] result: $(printf '%s' "$res" | grep -oE '"text":"[^"]*"' | head -c 300)"

got="$(printf '%s' "$res" | python3 -c "import json,sys; d=json.load(sys.stdin); t=d['result']['content'][0]['text']; o=json.loads(t); print('%.6f' % o['state'][0]); print('%.6f' % o['state'][1]); print(o.get('rounds_run','?')); print(o.get('converged','?'))" 2>/dev/null)"
C0="$(printf '%s' "$got" | sed -n 1p)"
C1="$(printf '%s' "$got" | sed -n 2p)"
rounds="$(printf '%s' "$got" | sed -n 3p)"
conv="$(printf '%s' "$got" | sed -n 4p)"

if python3 -c "import sys; exit(0 if (abs(float('$C0')-float('$O0'))<1e-3 and abs(float('$C1')-float('$O1'))<1e-3) else 1)" 2>/dev/null; then
    echo "[general-smoke] PASS k-means matched numpy Lloyd: c=[$C0, $C1] vs [$O0, $O1] (rounds=$rounds converged=$conv)"
else
    echo "[general-smoke] FAIL c=[$C0, $C1] oracle=[$O0, $O1]"; fail=1
fi

if [ "$fail" = 0 ]; then echo "[general-smoke] ALL PASS"; else echo "[general-smoke] FAILURES"; tail -25 "$TMP/node.log"; fi
exit $fail
