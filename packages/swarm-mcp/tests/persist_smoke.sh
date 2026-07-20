#!/usr/bin/env bash
# packages/swarm-mcp/tests/persist_smoke.sh — coordinator dataset persistence &
# crash-restart recovery. The --mcp coordinator holds the dataset registry in
# RAM; if it restarts, that used to be lost. Datasets are now persisted to
# $HOME/.swarm-mcp/datasets/ and reloaded on startup, so a restarted coordinator
# recovers them and a resubmit re-seeds from the persisted bytes.
#
# Uploads a dataset, KILLS the node, restarts it with the SAME $HOME, and checks
# (1) compute_list_data shows the recovered dataset, (2) a GPU reduce over it
# still returns the exact sum (blocks re-seeded from the persisted copy).
#
#   ./tests/persist_smoke.sh          # from the package root
# Skips (exit 0) without an NVIDIA GPU.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[persist-smoke] SKIP — no NVIDIA GPU visible"; exit 0
fi

PORT="${SWARM_PORT:-47903}"; MCPP="${SWARM_MCP_PORT:-48466}"
TOKEN="persist-smoke-secret"
TMP="$(mktemp -d)"; export HOME="$TMP"; export TMPDIR="$TMP"   # persists across restart
BIN="$TMP/swarm-mcp"; WT="$TMP/wt"; node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
MCP() { curl -sk -m 120 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }
start_node() {
    WASMTIME="$WT" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
        --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.$1.log" 2>&1 &
    node_pid=$!; sleep 2.5
}

echo "[persist-smoke] building swarm-mcp + wasmtime"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[persist-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/wasmtime/src/main.nu" "$WT" >/dev/null 2>&1 || { echo "[persist-smoke] FAIL build wt"; exit 1; }

# dataset: 100000 values, v[k] = 1.0 → sum = 100000, written to a file on the
# MCP host (the file survives in $HOME across the restart). Named, to check the
# name survives too.
N=100000
DS="$TMP/sensor.f64"
python3 -c "import struct; open('$DS','wb').write(struct.pack('<%dd'%$N, *([1.0]*$N)))"
fail=0

echo "[persist-smoke] run 1: upload dataset"
start_node 1
up="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_upload_data\",\"arguments\":{\"file\":\"$DS\",\"name\":\"sensor\"}}}")"
ds="$(printf '%s' "$up" | grep -oE 'dataset_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
[ -z "$ds" ] && { echo "[persist-smoke] FAIL upload: $up"; exit 1; }
echo "[persist-smoke] uploaded dataset_id=$ds; persisted files: $(ls "$TMP/.swarm-mcp/datasets" 2>/dev/null | tr '\n' ' ')"

echo "[persist-smoke] killing the coordinator (SIGKILL) and restarting with the same HOME"
kill -9 "$node_pid" 2>/dev/null; node_pid=""; sleep 1
start_node 2
grep -q "recovered .* dataset" "$TMP/node.2.log" && echo "[persist-smoke] node reports: $(grep 'recovered' "$TMP/node.2.log" | head -1)"

# 1. the dataset must reappear in the registry with the right count + name
ld="$(MCP '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"compute_list_data","arguments":{}}}')"
got="$(printf '%s' "$ld" | python3 -c "import json,sys
try:
    t=json.load(sys.stdin)['result']['content'][0]['text']; a=json.loads(t)
    d=[x for x in (a if isinstance(a,list) else a.get('datasets',[])) if x.get('dataset_id')==$ds]
    print('%s %s' % (d[0].get('count'), d[0].get('name')) if d else 'MISSING')
except Exception as e: print('ERR', e)" 2>/dev/null)"
if [ "$got" = "$N sensor" ]; then
    echo "[persist-smoke] PASS dataset recovered after restart (count=$N, name=sensor)"
else
    echo "[persist-smoke] FAIL registry after restart: '$got' (want '$N sensor')"; fail=1
    echo "--- run2 log ---"; tail -8 "$TMP/node.2.log"
fi

# 2. a GPU reduce over the recovered dataset must be exact (blocks re-seeded)
G='__device__ double f(long long x, double v) { return v; }'
req="$(python3 -c "import json,sys; print(json.dumps({'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':'compute_submit_cuda','arguments':{'cuda':sys.argv[1],'dataset':int(sys.argv[2]),'reduce':'sum'}}}))" "$G" "$ds")"
res="$(MCP "$req")"; tid="$(printf '%s' "$res" | grep -oE 'task_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
result=""; status=""
for _ in $(seq 1 40); do
    r="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$tid}}}")"
    read -r status result <<EOF
$(printf '%s' "$r" | python3 -c "import json,sys
try:
    o=json.loads(json.load(sys.stdin)['result']['content'][0]['text']); print(o.get('status',''), o.get('result','nan'))
except Exception: print('','nan')")
EOF
    case "$status" in done|error) break;; esac
    sleep 2
done
if [ "$status" = "done" ] && python3 -c "import sys; exit(0 if abs(float('$result')-float('$N'))<0.5 else 1)" 2>/dev/null; then
    echo "[persist-smoke] PASS GPU reduce over the recovered dataset is exact: $result == $N"
else
    echo "[persist-smoke] FAIL reduce after restart: status=$status result=$result (want $N)"; fail=1
fi

if [ "$fail" = 0 ]; then echo "[persist-smoke] ALL PASS"; else echo "[persist-smoke] FAILURES"; fi
exit $fail
