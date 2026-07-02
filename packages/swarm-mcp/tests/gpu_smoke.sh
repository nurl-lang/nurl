#!/usr/bin/env bash
# packages/swarm-mcp/tests/gpu_smoke.sh — live GPU end-to-end: build swarm-mcp
# and the pure-NURL wasmtime, start a --gpu node, and drive compute_submit_cuda
# over MCP HTTPS (the model-facing path): the server generates a CUDA kernel
# program around a __device__ map function, compiles it to wasm via the build
# API, and the GPU worker runs it under `wt --allow-gpu` on real hardware.
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
WT="$TMP/wt"
node_pid=""
cleanup() { [ -n "$node_pid" ] && kill -TERM "$node_pid" 2>/dev/null; sleep 0.3; [ -n "$node_pid" ] && kill -9 "$node_pid" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

MCP() { curl -sk -m 180 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[gpu-smoke] building swarm-mcp + pure-NURL wasmtime"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[gpu-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/wasmtime/src/main.nu" "$WT" >/dev/null 2>&1 || { echo "[gpu-smoke] FAIL build wt"; exit 1; }

echo "[gpu-smoke] starting node (relay + gpu worker + mcp) on :$PORT / :$MCPP"
WASMTIME="$WT" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/node.log" 2>&1 &
node_pid=$!
sleep 2.5

fail=0

# 1. compute_submit_cuda: ∫₀¹ 4/(1+t²) dt · 1e8 = π·1e8 — the whole chain:
#    generate → build API → wasm → GPU domain routing → wt --allow-gpu → CUDA.
sub="$(MCP '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"compute_submit_cuda","arguments":{"cuda":"__device__ double f(long long x) { double t = (double)x * 1e-8; return 4.0 / (1.0 + t*t); }","lo":0,"hi":100000000,"reduce":"sum"}}}')"
tid="$(printf '%s' "$sub" | grep -oE 'task_id..[0-9]+' | grep -oE '[0-9]+' | head -1)"
[ -z "$tid" ] && tid=1
ok=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    res="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$tid}}}")"
    if printf '%s' "$res" | grep -q '3.14159e+08'; then ok=1; break; fi
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
tid2="$(printf '%s' "$sub2" | grep -oE 'task_id..[0-9]+' | grep -oE '[0-9]+' | head -1)"
[ -z "$tid2" ] && tid2=2
ok2=0
for _ in 1 2 3 4 5 6 7 8; do
    res2="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$tid2}}}")"
    if printf '%s' "$res2" | grep -qF '1e+06'; then ok2=1; break; fi
    sleep 2
done
kill -9 "$cpu_pid" 2>/dev/null
if [ "$ok2" = 1 ]; then echo "[gpu-smoke] PASS GPU task routed around the CPU worker (mixed cluster)"; else
    echo "[gpu-smoke] FAIL mixed-cluster routing — last: $res2"; fail=1; fi

if [ "$fail" = 0 ]; then echo "[gpu-smoke] OK"; else echo "[gpu-smoke] FAILURES"; fi
exit "$fail"
