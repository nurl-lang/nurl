#!/usr/bin/env bash
# packages/swarm-mcp/tests/faulttol_smoke.sh — live in-computation fault
# tolerance: a GPU worker is KILLED mid-task and the coordinator must
# re-dispatch its chunk(s) to a surviving worker, so the task still finishes
# with the EXACT answer (no chunk silently lost).
#
# Topology (two SEPARATE GPU-worker processes so one can be killed):
#   node A: --relay --worker --gpu --mcp   (coordinator + GPU worker, device 0)
#   node B: --worker --gpu --connect A     (GPU worker, device 1) — the victim
#
# The kernel sums 1.0 over [0, N): the exact answer is N. A lost chunk would
# make the sum < N, so result == N proves every chunk was accounted for; the
# task's "retries" field proves the re-dispatch actually happened.
#
#   ./tests/faulttol_smoke.sh          # from the package root
# Skips (exit 0) with fewer than two visible NVIDIA GPUs.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[faulttol-smoke] SKIP — no NVIDIA GPU visible"; exit 0
fi
NGPU="$(nvidia-smi -L 2>/dev/null | grep -c '^GPU ')"
if [ "${NGPU:-0}" -lt 2 ]; then
    echo "[faulttol-smoke] SKIP — needs 2 GPUs to kill one worker and keep another (have ${NGPU:-0})"; exit 0
fi

PORT="${SWARM_PORT:-47898}"; MCPP="${SWARM_MCP_PORT:-48461}"
TOKEN="faulttol-smoke-secret"
TMP="$(mktemp -d)"; export HOME="$TMP"; export TMPDIR="$TMP"
BIN="$TMP/swarm-mcp"; NWASM="$TMP/nwasm"; a_pid=""; b_pid=""
cleanup() {
    for p in "$a_pid" "$b_pid"; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null; done
    rm -rf "$TMP"
}
trap cleanup EXIT
MCP() { curl -sk -m 180 "https://127.0.0.1:$MCPP/mcp" -H 'Content-Type: application/json' -d "$1"; }

echo "[faulttol-smoke] building swarm-mcp + nwasm"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1 || { echo "[faulttol-smoke] FAIL build swarm-mcp"; exit 1; }
"$NURL_SH" "$REPO/packages/nwasm/src/main.nu" "$NWASM" >/dev/null 2>&1 || { echo "[faulttol-smoke] FAIL build nwasm"; exit 1; }

echo "[faulttol-smoke] node A (relay+gpu worker+mcp) on device 0"
CUDA_VISIBLE_DEVICES=0 NURL_WASM_RUNTIME="$NWASM" "$BIN" --token "$TOKEN" --relay --worker --gpu --mcp \
    --listen 127.0.0.1:"$PORT" --mcp-listen 127.0.0.1:"$MCPP" >"$TMP/a.log" 2>&1 &
a_pid=$!; sleep 2.5

echo "[faulttol-smoke] node B (gpu worker, the victim) on device 1"
CUDA_VISIBLE_DEVICES=1 NURL_WASM_RUNTIME="$NWASM" "$BIN" --token "$TOKEN" --worker --gpu \
    --connect 127.0.0.1:"$PORT" >"$TMP/b.log" 2>&1 &
b_pid=$!; sleep 5

fail=0
N=800000000   # 8e8; kernel sums 1.0 → exact answer is 8e8 (representable in f64)
# Deliberately EXPENSIVE per element (a sin-accumulate loop feeding a guard that
# is always true) so a chunk takes several seconds — the victim cannot finish
# and reply inside the kill window, guaranteeing its chunk is genuinely in
# flight when it dies. The busy-work never changes the return (always 1.0), so
# the exact sum is still N.
KERNEL='__device__ double f(long long x) { double s = 0.0; for (int i = 0; i < 900; i++) { s += sin((double)(x + i)); } return (s == s) ? 1.0 : 0.0; }'

echo "[faulttol-smoke] submitting a $N-element GPU reduce across both workers"
sub="$(python3 -c "import json,sys; print(json.dumps({'jsonrpc':'2.0','id':1,'method':'tools/call','params':{'name':'compute_submit_cuda','arguments':{'cuda':sys.argv[1],'lo':0,'hi':$N,'reduce':'sum'}}}))" "$KERNEL")"
res="$(MCP "$sub")"
tid="$(printf '%s' "$res" | grep -oE 'task_id[^0-9]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
[ -z "$tid" ] && { echo "[faulttol-smoke] FAIL submit — $res"; exit 1; }
echo "[faulttol-smoke] task_id=$tid running; killing worker B (pid $b_pid) mid-flight"
sleep 2
kill -9 "$b_pid" 2>/dev/null; b_pid=""

# Poll to completion. The dead worker's chunk goes unanswered; after the
# re-dispatch deadline (~12s) the coordinator re-routes it to A, which finishes
# it. Allow generous time for that plus A computing all chunks.
final=""
for _ in $(seq 1 40); do
    r="$(MCP "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"compute_result\",\"arguments\":{\"task_id\":$tid}}}")"
    st="$(printf '%s' "$r" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); t=d['result']['content'][0]['text']; o=json.loads(t); print(o.get('status',''))
except Exception: print('')" 2>/dev/null)"
    if [ "$st" = "done" ] || [ "$st" = "error" ]; then final="$r"; break; fi
    sleep 2
done
[ -z "$final" ] && { echo "[faulttol-smoke] FAIL task never finished"; tail -15 "$TMP/a.log"; exit 1; }

read -r status result retries failed <<EOF
$(printf '%s' "$final" | python3 -c "import json,sys
d=json.load(sys.stdin); t=d['result']['content'][0]['text']; o=json.loads(t)
print(o.get('status',''), o.get('result','nan'), o.get('retries',0), o.get('failed_chunks',0))")
EOF
echo "[faulttol-smoke] final: status=$status result=$result retries=$retries failed_chunks=$failed"

if [ "$status" = "done" ] && python3 -c "import sys; exit(0 if abs(float('$result') - float('$N')) < 0.5 else 1)" 2>/dev/null; then
    echo "[faulttol-smoke] PASS exact result survived a worker death: $result == $N"
else
    echo "[faulttol-smoke] FAIL status=$status result=$result (want $N)"; fail=1
    echo "--- A log tail ---"; tail -20 "$TMP/a.log"
fi
if [ "${retries:-0}" -gt 0 ]; then
    echo "[faulttol-smoke] PASS the lost chunk was re-dispatched (retries=$retries)"
else
    echo "[faulttol-smoke] FAIL no re-dispatch recorded (retries=$retries) — the victim's chunk may not have been in flight"; fail=1
fi

if [ "$fail" = 0 ]; then echo "[faulttol-smoke] ALL PASS"; else echo "[faulttol-smoke] FAILURES"; fi
exit $fail
