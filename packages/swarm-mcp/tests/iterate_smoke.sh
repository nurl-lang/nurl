#!/usr/bin/env bash
# packages/swarm-mcp/tests/iterate_smoke.sh — live end-to-end for the
# iteration engine: gradient descent whose LOOP RUNS IN THE COORDINATOR.
# Upload a dataset, run compute_iterate to fit the mean by GD, and check
# (1) it converges to numpy's mean, (2) the data is cached after round one
# so the run reports seeded_blocks == the block count (moved once, not per
# round).
#
#   ./tests/iterate_smoke.sh          # from the package root
# Skips (exit 0) without an NVIDIA GPU. Needs curl + the build API.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[iterate-smoke] SKIP — no NVIDIA GPU visible"; exit 0
fi

PORT="${SWARM_PORT:-47894}"; MCPP="${SWARM_MCP_PORT:-48457}"
TOKEN="iterate-smoke-secret"
TMP="$(mktemp -d)"; export HOME="$TMP"; export TMPDIR="$TMP"
BIN="$TMP/swarm-mcp"; WT="$TMP/wt"; node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -TERM "$node_pid" 2>/dev/null; sleep 0.3; [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
MCP() { curl -sk -m 180 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[iterate-smoke] building swarm-mcp + wasmtime"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[iterate-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/wasmtime/src/main.nu" "$WT" >/dev/null 2>&1 || { echo "[iterate-smoke] FAIL build wt"; exit 1; }

# dataset: 3M values sampled from a fixed ramp; mean = (N-1)/2 * 1e-3
N=3000000
python3 - "$TMP/ds.f64" $N <<'PY'
import struct, sys
path, n = sys.argv[1], int(sys.argv[2])
with open(path, "wb") as f:
    for k in range(n): f.write(struct.pack("<d", k * 1e-3))
print("%.6f" % (sum(k*1e-3 for k in range(n))/n))
PY
MEAN="$(python3 -c "n=$N; print('%.4f' % (sum(k*1e-3 for k in range(n))/n))")"
echo "[iterate-smoke] target mean = $MEAN"

echo "[iterate-smoke] starting node on :$PORT / :$MCPP"
WASMTIME="$WT" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.log" 2>&1 &
node_pid=$!; sleep 2.5
fail=0

ds="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_upload_data\",\"arguments\":{\"file\":\"$TMP/ds.f64\"}}}" | grep -oE 'dataset_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
[ -z "$ds" ] && { echo "[iterate-smoke] FAIL upload"; exit 1; }

# GD to fit the mean: minimize sum (theta - v)^2 → grad_theta = sum 2(theta - v).
# state=[theta0=0], lr chosen so theta -= lr*grad/N = theta - 2*lr*(theta-mean)
# converges (lr < 0.5). 60 rounds is plenty; epsilon stops early.
GRAD='__device__ void grad(long long x, double v, double* g, const double* p) { swarm_g_add(g, 0, 2.0 * (p[0] - v)); }'
req="$(python3 -c "import json,sys; print(json.dumps({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'compute_iterate','arguments':{'cuda':sys.argv[1],'state':[0.0],'rounds':80,'lr':0.4,'epsilon':1e-4,'dataset':int(sys.argv[2])}}}))" "$GRAD" "$ds")"
res="$(MCP "$req")"
echo "[iterate-smoke] result: $(printf '%s' "$res" | grep -oE '"text":"[^"]*"' | head -c 300)"

got="$(printf '%s' "$res" | python3 -c "import json,sys; d=json.load(sys.stdin); import re; t=d['result']['content'][0]['text']; o=json.loads(t); print('%.4f' % o['state'][0]); print(o.get('seeded_blocks','?')); print(o.get('rounds_run','?')); print(o.get('converged','?'))" 2>/dev/null)"
theta="$(printf '%s' "$got" | sed -n 1p)"
seeded="$(printf '%s' "$got" | sed -n 2p)"
rounds="$(printf '%s' "$got" | sed -n 3p)"
conv="$(printf '%s' "$got" | sed -n 4p)"


if python3 -c "import sys; exit(0 if abs(float('$theta') - float('$MEAN')) < 1.0 else 1)" 2>/dev/null; then
    echo "[iterate-smoke] PASS GD converged to the mean: theta=$theta vs $MEAN (rounds=$rounds converged=$conv)"
else
    echo "[iterate-smoke] FAIL theta=$theta target=$MEAN"; fail=1
fi
NBLK=$(( (N + 131071) / 131072 ))
if [ "$seeded" = "$NBLK" ]; then
    echo "[iterate-smoke] PASS data moved ONCE across all $rounds rounds (seeded_blocks=$seeded == $NBLK blocks)"
else
    echo "[iterate-smoke] FAIL seeded_blocks=$seeded (want $NBLK — one seed per block over the whole run)"; fail=1
fi

if [ "$fail" = 0 ]; then echo "[iterate-smoke] ALL PASS"; else echo "[iterate-smoke] FAILURES"; tail -20 "$TMP/node.log"; fi
exit $fail
