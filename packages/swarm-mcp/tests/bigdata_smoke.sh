#!/usr/bin/env bash
# packages/swarm-mcp/tests/bigdata_smoke.sh — file-backed datasets larger than
# coordinator RAM. A dataset used to be capped at 256 MiB because the whole
# thing was held in the coordinator's memory. A "file" upload now STREAMS the
# manifest + stats from disk and seeds blocks straight from the file, so the
# size is bounded by disk, not RAM.
#
# This test uploads a file BIGGER than the old 256 MiB cap, runs a GPU reduce
# whose exact answer is known, and checks:
#   1. the upload is accepted (it would have been rejected before) as file_backed,
#   2. the GPU reduce over the whole file returns the exact sum,
#   3. the coordinator's peak RSS stays well under the file size (it streams).
#
#   ./tests/bigdata_smoke.sh          # from the package root
# Skips (exit 0) without an NVIDIA GPU.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[bigdata-smoke] SKIP — no NVIDIA GPU visible"; exit 0
fi

PORT="${SWARM_PORT:-47900}"; MCPP="${SWARM_MCP_PORT:-48463}"
TOKEN="bigdata-smoke-secret"
TMP="$(mktemp -d)"; export HOME="$TMP"; export TMPDIR="$TMP"
BIN="$TMP/swarm-mcp"; NWASM="$TMP/nwasm"; node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
MCP() { curl -sk -m 600 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[bigdata-smoke] building swarm-mcp + nwasm"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[bigdata-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/nwasm/src/main.nu" "$NWASM" >/dev/null 2>&1 || { echo "[bigdata-smoke] FAIL build nwasm"; exit 1; }

# A 320 MiB dataset (> the old 256 MiB cap): 40M f64 values, all 1.0 → sum = 40M.
NVAL=41943040   # 40 * 1024 * 1024 → 320 MiB exactly
DS="$TMP/big.f64"
echo "[bigdata-smoke] writing a $((NVAL*8/1024/1024)) MiB dataset (all 1.0) → $DS"
python3 - "$DS" "$NVAL" <<'PY'
import struct, sys
path, n = sys.argv[1], int(sys.argv[2])
one = struct.pack("<d", 1.0)
buf = one * 65536
with open(path, "wb") as f:
    full, rem = divmod(n, 65536)
    for _ in range(full): f.write(buf)
    if rem: f.write(one * rem)
PY
FSZ=$(stat -c %s "$DS"); echo "[bigdata-smoke] file is $FSZ bytes ($((FSZ/1024/1024)) MiB), old cap was 256 MiB"

echo "[bigdata-smoke] starting node on :$PORT / :$MCPP"
NURL_WASM_RUNTIME="$NWASM" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.log" 2>&1 &
node_pid=$!; sleep 2.5
fail=0

# RSS sampler: record the coordinator's peak resident memory during the run.
peak_rss_kb=0
sample_rss() { local r; r=$(awk '/VmRSS/{print $2}' /proc/$node_pid/status 2>/dev/null); [ -n "$r" ] && [ "$r" -gt "$peak_rss_kb" ] && peak_rss_kb=$r; }

up="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_upload_data\",\"arguments\":{\"file\":\"$DS\",\"name\":\"big\"}}}")"
sample_rss
echo "[bigdata-smoke] upload result: $(printf '%s' "$up" | grep -oE '"text":"[^"]*"' | head -c 260)"
ds="$(printf '%s' "$up" | grep -oE 'dataset_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
fb="$(printf '%s' "$up" | grep -c 'file_backed')"
if [ -n "$ds" ] && [ "$fb" -ge 1 ]; then
    echo "[bigdata-smoke] PASS a >256 MiB file was accepted as a file-backed dataset (id=$ds)"
else
    echo "[bigdata-smoke] FAIL upload rejected or not file-backed: $up"; exit 1
fi

# GPU reduce over the whole dataset: sum of 1.0 over every element == NVAL.
GRAD='__device__ double f(long long x, double v) { return v; }'
req="$(python3 -c "import json,sys; print(json.dumps({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'compute_submit_cuda','arguments':{'cuda':sys.argv[1],'dataset':int(sys.argv[2]),'reduce':'sum'}}}))" "$GRAD" "$ds")"
res="$(MCP "$req")"
tid="$(printf '%s' "$res" | grep -oE 'task_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
[ -z "$tid" ] && { echo "[bigdata-smoke] FAIL submit: $res"; exit 1; }

result=""; status=""
for _ in $(seq 1 90); do
    sample_rss
    r="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$tid}}}")"
    read -r status result <<EOF
$(printf '%s' "$r" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); o=json.loads(d['result']['content'][0]['text']); print(o.get('status',''), o.get('result','nan'))
except Exception: print('', 'nan')")
EOF
    case "$status" in done|error) break;; esac
    sleep 2
done
echo "[bigdata-smoke] reduce: status=$status result=$result (want $NVAL)"

if [ "$status" = "done" ] && python3 -c "import sys; exit(0 if abs(float('$result') - float('$NVAL')) < 0.5 else 1)" 2>/dev/null; then
    echo "[bigdata-smoke] PASS GPU reduce over the whole file is exact: $result == $NVAL"
else
    echo "[bigdata-smoke] FAIL status=$status result=$result"; fail=1; tail -20 "$TMP/node.log"
fi

# The coordinator must NOT have loaded the 320 MiB file into RAM — peak RSS well
# under the file size proves the streaming path (allow 128 MiB headroom for the
# process, module cache, TLS, etc. — still far below the 320 MiB file).
peak_mib=$(( peak_rss_kb / 1024 ))
echo "[bigdata-smoke] coordinator peak RSS = ${peak_mib} MiB; file = $((FSZ/1024/1024)) MiB"
if [ "$peak_mib" -lt 200 ]; then
    echo "[bigdata-smoke] PASS coordinator streamed the file (peak RSS ${peak_mib} MiB << $((FSZ/1024/1024)) MiB)"
else
    echo "[bigdata-smoke] FAIL coordinator RSS ${peak_mib} MiB suggests it held the whole file"; fail=1
fi

if [ "$fail" = 0 ]; then echo "[bigdata-smoke] ALL PASS"; else echo "[bigdata-smoke] FAILURES"; fi
exit $fail
