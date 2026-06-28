#!/usr/bin/env bash
# packages/swarm/tests/live_smoke.sh — build the swarm binary and run a real
# distributed workload across a local relay + worker set, end to end.
#
#   ./tests/live_smoke.sh
#
# Run from the package root (packages/swarm). Expects the monorepo layout so
# NURL_STDLIB resolves. Starts its own relay and workers on a high port; needs
# no network beyond loopback.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"          # packages/swarm
REPO="$(cd "$HERE/../.." && pwd)"                  # repo root
NURL_SH="$REPO/nurl.sh"
export NURL_STDLIB="$REPO"

PORT="${SWARM_PORT:-47780}"
WORKERS="${SWARM_WORKERS:-3}"
TMP="$(mktemp -d)"
BIN="$TMP/swarm"
pids=()
cleanup() { for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done; rm -rf "$TMP"; }
trap cleanup EXIT

echo "[smoke] building swarm"
"$NURL_SH" "$HERE/src/main.nu" "$BIN" >/dev/null 2>&1

echo "[smoke] starting relay on :$PORT"
"$BIN" relay 127.0.0.1 "$PORT" >"$TMP/relay.log" 2>&1 &
pids+=($!)
sleep 0.6

echo "[smoke] starting $WORKERS workers"
for i in $(seq 1 "$WORKERS"); do
    "$BIN" worker 127.0.0.1 "$PORT" "$i" 0 >"$TMP/w$i.log" 2>&1 &
    pids+=($!)
done
sleep 1.0

fail=0
check() {  # <label> <expected> <output>
    local label="$1" want="$2" out="$3"
    if echo "$out" | grep -q "result = $want"; then
        echo "[smoke] PASS $label (= $want)"
    else
        echo "[smoke] FAIL $label — wanted $want, got:"; echo "$out" | sed 's/^/    /'
        fail=1
    fi
}

# π(100000) = 9592 — a genuine distributed prime count, sharded by key.
out="$("$BIN" submit 127.0.0.1 "$PORT" primes 1 100000 2>&1)"
check "primes 1..100000" 9592 "$out"

# Σ k² for k in [0,1000) = 999·1000·1999/6 = 332833500.
out="$("$BIN" submit 127.0.0.1 "$PORT" sumsq 0 1000 2>&1)"
check "sumsq 0..1000" 332833500 "$out"

if [ "$fail" = 0 ]; then echo "[smoke] OK"; else echo "[smoke] FAILED"; exit 1; fi
