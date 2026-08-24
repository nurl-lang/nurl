#!/usr/bin/env bash
# packages/swarm-mcp/tests/gpu_smoke.sh — live GPU end-to-end: build swarm-mcp
# and the pure-NURL nwasm runtime, start a --gpu node, and drive compute_submit_cuda
# over MCP HTTPS (the model-facing path): the server generates a CUDA kernel
# program around a __device__ map function, compiles it to wasm via the build
# API, and the GPU worker runs it under `nwasm --allow-gpu` on real hardware.
#
#   ./tests/gpu_smoke.sh          # from the package root
#
# Skips (exit 0) when no NVIDIA GPU / libcuda is present. Needs curl and a
# reachable NURL build API ($NURL_BUILD_API, default https://play.nurl-lang.org).
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[gpu-smoke] SKIP — no NVIDIA GPU visible"; exit 0
fi

PORT="${SWARM_PORT:-47890}"
MCPP="${SWARM_MCP_PORT:-48453}"
TOKEN="gpu-smoke-secret"
TMP="$(mktemp -d)"
export HOME="$TMP"
BIN="$TMP/swarm-mcp"
NWASM="$TMP/nwasm"
node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -TERM "$node_pid" 2>/dev/null; sleep 0.3; [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

MCP() { curl -sk -m 180 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[gpu-smoke] building swarm-mcp + the pure-NURL nwasm"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[gpu-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/nwasm/src/main.nu" "$NWASM" >/dev/null 2>&1 || { echo "[gpu-smoke] FAIL build nwasm"; exit 1; }

echo "[gpu-smoke] starting node (relay + gpu worker + mcp) on :$PORT / :$MCPP"
NURL_WASM_RUNTIME="$NWASM" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.log" 2>&1 &
node_pid=$!
sleep 2.5

fail=0

# 1. compute_submit_cuda: ∫₀¹ 4/(1+t²) dt · 1e8 = π·1e8 — the whole chain:
#    generate → build API → wasm → GPU domain routing → nwasm --allow-gpu → CUDA.
sub="$(MCP '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"compute_submit_cuda","arguments":{"cuda":"__device__ double f(long long x) { double t = (double)x * 1e-8; return 4.0 / (1.0 + t*t); }","lo":0,"hi":100000000,"reduce":"sum"}}}')"
tid="$(printf '%s' "$sub" | grep -oE 'task_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
[ -z "$tid" ] && tid=1
ok=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    res="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$tid}}}")"
    if printf '%s' "$res" | grep -qE 'result[^0-9]{1,4}31415926'; then ok=1; break; fi
    sleep 2
done
if [ "$ok" = 1 ]; then echo "[gpu-smoke] PASS compute_submit_cuda π·1e8 on the GPU"; else
    echo "[gpu-smoke] FAIL compute_submit_cuda — last: $res"; fail=1; fi

# 2. heterogeneous routing: join a NON-gpu worker; a fresh GPU task must still
#    complete (GPU chunks route on the GPU capability ring, never to the CPU
#    worker, which has no kind_wasm_gpu handler).
"$BIN" --token "$TOKEN" --worker --connect 127.0.0.1:"$PORT" >"$TMP/cpuworker.log" 2>&1 &
cpu_pid=$!
sleep 1.5
sub2="$(MCP '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"compute_submit_cuda","arguments":{"cuda":"__device__ double f(long long x) { return 1.0; }","lo":0,"hi":1000000,"reduce":"sum"}}}')"
tid2="$(printf '%s' "$sub2" | grep -oE 'task_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
[ -z "$tid2" ] && tid2=2
ok2=0
for _ in 1 2 3 4 5 6 7 8; do
    res2="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$tid2}}}")"
    if printf '%s' "$res2" | grep -qE 'result[^0-9]{1,4}1000000'; then ok2=1; break; fi
    sleep 2
done
kill -9 "$cpu_pid" 2>/dev/null
if [ "$ok2" = 1 ]; then echo "[gpu-smoke] PASS GPU task routed around the CPU worker (mixed cluster)"; else
    echo "[gpu-smoke] FAIL mixed-cluster routing — last: $res2"; fail=1; fi

# 3. runtime params + the coordinator module cache: same source, two params —
#    the second submit must skip the build API (fast) and scale the result.
p1="$(MCP '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"compute_submit_cuda","arguments":{"cuda":"__device__ double f(long long x, const double* p) { return p[0] * (double)x; }","lo":0,"hi":1000,"reduce":"sum","params":[2.0]}}}')"
t0=$(date +%s)
p2="$(MCP '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"compute_submit_cuda","arguments":{"cuda":"__device__ double f(long long x, const double* p) { return p[0] * (double)x; }","lo":0,"hi":1000,"reduce":"sum","params":[3.0]}}}')"
t1=$(date +%s)
ok3=0
if printf '%s' "$p1" | grep -qF '999000' && printf '%s' "$p2" | grep -qF '1498500' && [ $((t1 - t0)) -le 10 ]; then ok3=1; fi
if [ "$ok3" = 1 ]; then echo "[gpu-smoke] PASS runtime params + warm module cache ($((t1 - t0))s warm submit)"; else
    echo "[gpu-smoke] FAIL params/cache — p1: $p1 p2: $p2 warm=$((t1 - t0))s"; fail=1; fi

# 4. compute_sample_cuda: 16 values of 0.25x come back in order
sm="$(MCP '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"compute_sample_cuda","arguments":{"cuda":"__device__ double f(long long x) { return 0.25 * (double)x; }","lo":0,"hi":16}}}')"
if printf '%s' "$sm" | grep -qF '0.25' && printf '%s' "$sm" | grep -qF '3.75' && printf '%s' "$sm" | grep -qE 'count.":16'; then
    echo "[gpu-smoke] PASS compute_sample_cuda (16 ordered values)"; else
    echo "[gpu-smoke] FAIL compute_sample_cuda — $sm"; fail=1; fi

# 5. compute_histogram_cuda: x%8 over [0,1e6) → 8 bins of 125000
hs="$(MCP '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"compute_histogram_cuda","arguments":{"cuda":"__device__ long long bin(long long x) { return x % 8; }","lo":0,"hi":1000000,"bins":8}}}')"
htid="$(printf '%s' "$hs" | grep -oE 'task_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
[ -z "$htid" ] && htid=5
hok=0
for _ in 1 2 3 4 5 6 7 8; do
    hres="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$htid}}}")"
    if [ "$(printf '%s' "$hres" | grep -oF '125000' | wc -l)" -ge 8 ]; then hok=1; break; fi
    sleep 2
done
if [ "$hok" = 1 ]; then echo "[gpu-smoke] PASS compute_histogram_cuda (8 × 125000)"; else
    echo "[gpu-smoke] FAIL compute_histogram_cuda — $hres"; fail=1; fi

# 6. datasets: upload 16 values 0..15 (raw LE f64 base64), GPU-reduce over the
#    data (Σv = 120), then a histogram of the data itself (4 bins × 4).
if command -v python3 >/dev/null 2>&1; then
    DB64="$(python3 -c "import struct,base64;print(base64.b64encode(struct.pack('<16d',*range(16))).decode())")"
    up="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_upload_data\",\"arguments\":{\"data_base64\":\"$DB64\",\"name\":\"smoke16\"}}}")"
    dsid="$(printf '%s' "$up" | grep -oE 'dataset_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
    [ -z "$dsid" ] && dsid=1
    dres="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_submit_cuda\",\"arguments\":{\"cuda\":\"__device__ double f(long long x, double v) { return v; }\",\"dataset\":$dsid,\"reduce\":\"sum\"}}}")"
    dh="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_histogram_cuda\",\"arguments\":{\"cuda\":\"__device__ long long bin(long long x, double v) { return (long long)(v / 4.0); }\",\"dataset\":$dsid,\"bins\":4}}}")"
    if printf '%s' "$dres" | grep -qF '120' && [ "$(printf '%s' "$dh" | grep -oF ',4,4,' | wc -l)" -ge 1 ]; then
        echo "[gpu-smoke] PASS datasets (upload + GPU reduce Σv=120 + data histogram 4×4)"; else
        echo "[gpu-smoke] FAIL datasets — up: $up dres: $dres dh: $dh"; fail=1; fi
else
    echo "[gpu-smoke] SKIP datasets subtest (no python3 to build the base64 fixture)"
fi

if [ "$fail" = 0 ]; then echo "[gpu-smoke] OK"; else echo "[gpu-smoke] FAILURES"; fi
exit "$fail"
