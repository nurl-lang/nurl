#!/usr/bin/env bash
# packages/swarm-mcp/tests/data_smoke.sh — live end-to-end for the
# content-addressed data layer: upload a 2-block dataset, run the same
# CUDA reduce TWICE, and require (1) the correct sum both times, (2)
# seeded_blocks=2 on the first submit and 0 on the second (the re-run
# ships hashes only), (3) the blocks present in the worker's disk cache.
#
#   ./tests/data_smoke.sh          # from the package root
# Skips (exit 0) without an NVIDIA GPU. Needs curl + the build API.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[data-smoke] SKIP — no NVIDIA GPU visible"; exit 0
fi

PORT="${SWARM_PORT:-47892}"
MCPP="${SWARM_MCP_PORT:-48455}"
TOKEN="data-smoke-secret"
TMP="$(mktemp -d)"
export HOME="$TMP"
export TMPDIR="$TMP"
BIN="$TMP/swarm-mcp"
WT="$TMP/wt"
node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -TERM "$node_pid" 2>/dev/null; sleep 0.3; [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

MCP() { curl -sk -m 180 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[data-smoke] building swarm-mcp + wasmtime"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[data-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/wasmtime/src/main.nu" "$WT" >/dev/null 2>&1 || { echo "[data-smoke] FAIL build wt"; exit 1; }

# dataset: 1.5M values v[k] = k*1e-3 → sum = 1e-3·N(N−1)/2 (2 blocks)
N=1500000
python3 - "$TMP/ds.f64" $N <<'PY'
import struct, sys
path, n = sys.argv[1], int(sys.argv[2])
with open(path, "wb") as f:
    for k in range(n):
        f.write(struct.pack("<d", k * 1e-3))
print("expected sum: %g" % (1e-3 * n * (n - 1) / 2))
PY
EXPECT="1.125e+09"

echo "[data-smoke] starting node on :$PORT / :$MCPP"
WASMTIME="$WT" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.log" 2>&1 &
node_pid=$!
sleep 2.5

fail=0

up="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_upload_data\",\"arguments\":{\"file\":\"$TMP/ds.f64\",\"name\":\"ramp\"}}}")"
ds="$(printf '%s' "$up" | grep -oE 'dataset_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
if [ -z "$ds" ]; then echo "[data-smoke] FAIL upload — $up"; exit 1; fi
echo "[data-smoke] dataset id=$ds"

run_sum() { # $1 = jsonrpc id → prints "taskid seeded"
    local sub tid seeded
    sub="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":$1,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_submit_cuda\",\"arguments\":{\"cuda\":\"__device__ double f(long long x, double v) { return v; }\",\"dataset\":$ds,\"reduce\":\"sum\"}}}")"
    tid="$(printf '%s' "$sub" | grep -oE 'task_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
    seeded="$(printf '%s' "$sub" | grep -oE 'seeded_blocks[^0-9]*[0-9]+' | grep -oE '[0-9]+' | tail -1)"
    echo "${tid:-0} ${seeded:--1}"
}

wait_result() { # $1 = task id, $2 = jsonrpc id → 0 when EXPECT seen
    local res
    for _ in $(seq 1 15); do
        res="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":$2,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$1}}}")"
        if printf '%s' "$res" | grep -q "$EXPECT"; then return 0; fi
        sleep 2
    done
    echo "[data-smoke] last result: $res"
    return 1
}

read -r tid1 seeded1 <<<"$(run_sum 2)"
if [ "$seeded1" = 12 ]; then echo "[data-smoke] PASS first submit seeded all 12 blocks"; else
    echo "[data-smoke] FAIL first submit seeded_blocks=$seeded1 (want 12)"; fail=1; fi
if wait_result "$tid1" 3; then echo "[data-smoke] PASS sum #1 = $EXPECT"; else
    echo "[data-smoke] FAIL sum #1"; fail=1; fi

nblob="$(ls "$TMP"/swarmb_*.blob 2>/dev/null | wc -l)"
if [ "$nblob" = 12 ]; then echo "[data-smoke] PASS all 12 blocks in the worker cache"; else
    echo "[data-smoke] FAIL blob cache has $nblob files (want 12)"; fail=1; fi

read -r tid2 seeded2 <<<"$(run_sum 4)"
if [ "$seeded2" = 0 ]; then echo "[data-smoke] PASS second submit seeded 0 blocks (hashes only)"; else
    echo "[data-smoke] FAIL second submit seeded_blocks=$seeded2 (want 0)"; fail=1; fi
if wait_result "$tid2" 5; then echo "[data-smoke] PASS sum #2 = $EXPECT (from cached blocks)"; else
    echo "[data-smoke] FAIL sum #2"; fail=1; fi

if [ "$fail" = 0 ]; then echo "[data-smoke] ALL PASS"; else echo "[data-smoke] FAILURES"; tail -20 "$TMP/node.log"; fi
exit $fail
