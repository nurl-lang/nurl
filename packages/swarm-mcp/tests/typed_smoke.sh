#!/usr/bin/env bash
# packages/swarm-mcp/tests/typed_smoke.sh — TYPED datasets (f32 / i32), not just
# f64. Real data is usually 32-bit; storing it natively halves transfer/GPU
# memory. The element is promoted to a double on the GPU, so the kernel still
# writes f(long long x, double v) regardless of storage type.
#
# Uploads an f32 file and an i32 file, reduces each on the GPU, and checks the
# sum matches numpy (accumulated in float64, as the GPU does). Also confirms the
# reported dtype and element count.
#
#   ./tests/typed_smoke.sh          # from the package root
# Skips (exit 0) without an NVIDIA GPU.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[typed-smoke] SKIP — no NVIDIA GPU visible"; exit 0
fi

PORT="${SWARM_PORT:-47901}"; MCPP="${SWARM_MCP_PORT:-48464}"
TOKEN="typed-smoke-secret"
TMP="$(mktemp -d)"; export HOME="$TMP"; export TMPDIR="$TMP"
BIN="$TMP/swarm-mcp"; NWASM="$TMP/nwasm"; node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
MCP() { curl -sk -m 180 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[typed-smoke] building swarm-mcp + nwasm"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[typed-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/nwasm/src/main.nu" "$NWASM" >/dev/null 2>&1 || { echo "[typed-smoke] FAIL build nwasm"; exit 1; }

# f32: v[k] = (k % 7) as float32 (exact); i32: v[k] = (k % 1000) as int32.
N=3000000
python3 - "$TMP/f32.bin" "$TMP/i32.bin" "$N" "$TMP/oracle.txt" <<'PY'
import numpy as np, sys
pf, pi, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
a32 = (np.arange(n) % 7).astype("<f4"); a32.tofile(pf)
i32 = (np.arange(n) % 1000).astype("<i4"); i32.tofile(pi)
# GPU accumulates in float64 → oracle uses float64 accumulation
open(sys.argv[4], "w").write("%.1f %.1f" % (a32.sum(dtype=np.float64), i32.sum(dtype=np.float64)))
PY
read -r SUM_F32 SUM_I32 < "$TMP/oracle.txt"
echo "[typed-smoke] numpy oracle: f32 sum=$SUM_F32  i32 sum=$SUM_I32"

echo "[typed-smoke] starting node on :$PORT / :$MCPP"
NURL_WASM_RUNTIME="$NWASM" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.log" 2>&1 &
node_pid=$!; sleep 2.5
fail=0

# $1 file, $2 dtype, $3 expected-sum, $4 label
run_case() {
    local file="$1" dtype="$2" want="$3" label="$4"
    local up ds cnt dt
    up="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_upload_data\",\"arguments\":{\"file\":\"$file\",\"dtype\":\"$dtype\"}}}")"
    read -r ds cnt dt <<EOF
$(printf '%s' "$up" | python3 -c "import json,sys
try:
    o=json.loads(json.load(sys.stdin)['result']['content'][0]['text']); print(o.get('dataset_id'), o.get('count'), o.get('dtype'))
except Exception: print('', '', '')")
EOF
    if [ -z "$ds" ]; then echo "[typed-smoke] FAIL $label upload: $up"; fail=1; return; fi
    if [ "$cnt" != "$N" ] || [ "$dt" != "$dtype" ]; then
        echo "[typed-smoke] FAIL $label metadata: count=$cnt (want $N) dtype=$dt (want $dtype)"; fail=1; return
    fi
    echo "[typed-smoke] PASS $label upload: id=$ds count=$cnt dtype=$dt"
    local G='__device__ double f(long long x, double v) { return v; }'
    local req res tid st result
    req="$(python3 -c "import json,sys; print(json.dumps({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'compute_submit_cuda','arguments':{'cuda':sys.argv[1],'dataset':int(sys.argv[2]),'reduce':'sum'}}}))" "$G" "$ds")"
    res="$(MCP "$req")"; tid="$(printf '%s' "$res" | grep -oE 'task_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
    [ -z "$tid" ] && { echo "[typed-smoke] FAIL $label submit: $res"; fail=1; return; }
    for _ in $(seq 1 60); do
        res="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$tid}}}")"
        read -r st result <<EOF
$(printf '%s' "$res" | python3 -c "import json,sys
try:
    o=json.loads(json.load(sys.stdin)['result']['content'][0]['text']); print(o.get('status',''), o.get('result','nan'))
except Exception: print('', 'nan')")
EOF
        case "$st" in done|error) break;; esac
        sleep 2
    done
    if [ "$st" = "done" ] && python3 -c "import sys; exit(0 if abs(float('$result')-float('$want'))<0.5 else 1)" 2>/dev/null; then
        echo "[typed-smoke] PASS $label GPU reduce = $result (matches numpy $want)"
    else
        echo "[typed-smoke] FAIL $label reduce: status=$st result=$result want=$want"; fail=1
        tail -15 "$TMP/node.log"
    fi
}

run_case "$TMP/f32.bin" f32 "$SUM_F32" "f32"
run_case "$TMP/i32.bin" i32 "$SUM_I32" "i32"

if [ "$fail" = 0 ]; then echo "[typed-smoke] ALL PASS"; else echo "[typed-smoke] FAILURES"; fi
exit $fail
