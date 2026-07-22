#!/usr/bin/env bash
# packages/swarm-mcp/tests/grad_iterate_smoke.sh — M7-2 live: the
# compute_iterate kernel is DERIVED, not hand-written. grad's
# tests/swarm_linreg_dump.nu builds a linear-regression loss on the
# autograd tape, emits it as the __device__ grad() via gemit_cuda_grad,
# and runs the same GD locally as the reference; this script feeds the
# EMITTED kernel to a live cluster through compute_iterate and asserts
# the distributed parameters land on the local tape's (atomicAdd/combine
# order differs → tolerance, not bits; the bit-level tape↔C equivalence
# is grad/tests/emitc_oracle.sh's job).
#
#   ./tests/grad_iterate_smoke.sh     # from the package root
# Skips (exit 0) without an NVIDIA GPU.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[grad-iterate] SKIP — no NVIDIA GPU visible"; exit 0
fi

PORT="${SWARM_PORT:-47895}"; MCPP="${SWARM_MCP_PORT:-48458}"
TOKEN="grad-iterate-secret"
TMP="$(mktemp -d)"; export HOME="$TMP"; export TMPDIR="$TMP"
BIN="$TMP/swarm-mcp"; WT="$TMP/wt"; node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -TERM "$node_pid" 2>/dev/null; sleep 0.3; [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
MCP() { curl -sk -m 180 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[grad-iterate] building the tape dump (packages/grad)"
( cd "$REPO/packages/grad" && "$NURL_SH" tests/swarm_linreg_dump.nu "$TMP/dump" >/dev/null 2>&1 ) \
    || { echo "[grad-iterate] FAIL build dump"; exit 1; }
"$TMP/dump" > "$TMP/dump.txt" || { echo "[grad-iterate] FAIL run dump"; exit 1; }
awk '/===SRC===/{f=1;next}/===REF===/{f=0}f' "$TMP/dump.txt" > "$TMP/grad.cu"
REF_A="$(awk '/===REF===/{getline; print; exit}' "$TMP/dump.txt")"
REF_B="$(awk '/===REF===/{getline; getline; print; exit}' "$TMP/dump.txt")"
N="$(awk '/===CFG===/{getline; print; exit}' "$TMP/dump.txt")"
LR="$(awk '/===CFG===/{getline; getline; print; exit}' "$TMP/dump.txt")"
ROUNDS="$(awk '/===CFG===/{getline; getline; getline; print; exit}' "$TMP/dump.txt")"
echo "[grad-iterate] emitted kernel: $(wc -l < "$TMP/grad.cu") lines · local tape ref a=$REF_A b=$REF_B (N=$N lr=$LR rounds=$ROUNDS)"

echo "[grad-iterate] building swarm-mcp + wasmtime"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[grad-iterate] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/wasmtime/src/main.nu" "$WT" >/dev/null 2>&1 || { echo "[grad-iterate] FAIL build wt"; exit 1; }

# the dataset the dump's reference used: v_k = 2.5·(k·0.001) − 1.2
python3 - "$TMP/ds.f64" "$N" <<'PY'
import struct, sys
path, n = sys.argv[1], int(sys.argv[2])
with open(path, "wb") as f:
    for k in range(n): f.write(struct.pack("<d", 2.5 * (k * 0.001) - 1.2))
PY

echo "[grad-iterate] starting node on :$PORT / :$MCPP"
WASMTIME="$WT" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.log" 2>&1 &
node_pid=$!; sleep 2.5

ds="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_upload_data\",\"arguments\":{\"file\":\"$TMP/ds.f64\"}}}" | grep -oE 'dataset_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
[ -z "$ds" ] && { echo "[grad-iterate] FAIL upload"; cat "$TMP/node.log" | tail -5; exit 1; }

req="$(python3 -c "
import json, sys
src = open(sys.argv[1]).read()
print(json.dumps({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'compute_iterate','arguments':{'cuda':src,'state':[0.0,0.0],'rounds':int(sys.argv[3]),'lr':float(sys.argv[4]),'dataset':int(sys.argv[2])}}}))
" "$TMP/grad.cu" "$ds" "$ROUNDS" "$LR")"
res="$(MCP "$req")"

got="$(printf '%s' "$res" | python3 -c "import json,sys; d=json.load(sys.stdin); t=d['result']['content'][0]['text']; o=json.loads(t); print(repr(o['state'][0])); print(repr(o['state'][1]))" 2>/dev/null)"
A="$(printf '%s' "$got" | sed -n 1p)"
B="$(printf '%s' "$got" | sed -n 2p)"
echo "[grad-iterate] swarm result a=$A b=$B"

if python3 -c "
import sys
a, b = float('$A'), float('$B')
ra, rb = float('$REF_A'), float('$REF_B')
ok = abs(a - ra) < 1e-6 and abs(b - rb) < 1e-6
ok2 = abs(a - 2.5) < 0.05 and abs(b + 1.2) < 0.05
sys.exit(0 if (ok and ok2) else 1)
"; then
    echo "[grad-iterate] PASS — DERIVED kernel trained on the swarm lands on the local tape reference (|Δ| < 1e-6) and the true line (2.5, −1.2)"
else
    echo "[grad-iterate] FAIL — swarm ($A,$B) vs tape ref ($REF_A,$REF_B)"
    tail -5 "$TMP/node.log"
    exit 1
fi
