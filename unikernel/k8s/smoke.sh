#!/usr/bin/env bash
# ============================================================
#  unikernel/k8s/smoke.sh — boot the server the deployment ships and
#  ask it the four questions the deployment asks it.
#
#  Usage: unikernel/k8s/smoke.sh [image.elf]
#
#  The interesting assertions are the last two, and neither is about
#  whether the server answers. A machine that boots and serves is not
#  news; one that boots and serves QUICKLY, to more than one client at
#  a time, is the whole claim — and all three bugs this directory's
#  README describes were invisible to every "does it answer" test in
#  the repository. So the budget is asserted, not printed:
#  from the hypervisor's first instruction to a client holding a
#  response, one second — against 63 ms measured, which leaves room for
#  a loaded CI box and none for a regression.
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMG="${1:-${NURL_UNIKERNEL_OUT:-$ROOT/build/unikernel}/k8sd.elf}"
QEMU="${QEMU:-qemu-system-x86_64}"
PORT="${SMOKE_PORT:-18771}"
BUDGET_MS="${SMOKE_BUDGET_MS:-1000}"
LOG="$(mktemp)"
fails=0

[ -f "$IMG" ] || { echo "smoke.sh: no image at $IMG — run build_image.sh or build_unikernel.sh" >&2; exit 2; }
command -v "$QEMU" >/dev/null 2>&1 || { echo "smoke.sh: $QEMU not found" >&2; exit 3; }
command -v curl >/dev/null 2>&1 || { echo "smoke.sh: curl not found" >&2; exit 3; }

ACCEL=tcg
[ -w /dev/kvm ] && ACCEL=kvm

# The host's nominal TSC frequency, for the same reason entrypoint.sh
# derives it: under TCG the guest's rdtsc IS the host's, so 1 GHz would
# make every guest timer run at the host's TSC ratio to it.
TSC_KHZ="$(sed -n 's/^model name.*@ *\([0-9.]*\)GHz.*/\1/p' /proc/cpuinfo | head -1 |
           awk '{ printf "%d", $1 * 1000000 }')"
[ -n "$TSC_KHZ" ] || TSC_KHZ=1000000

start_ns=$(date +%s%N)
"$QEMU" -M microvm,acpi=off,rtc=off \
    -accel "$ACCEL" -cpu max -m 256 \
    -nodefaults -no-reboot -no-user-config \
    -global virtio-mmio.force-legacy=false \
    -kernel "$IMG" \
    -append "tsc_khz=${TSC_KHZ} wallclock=$(date +%s) pod=smoke port=8080 platform=unikernel" \
    -device virtio-net-device,netdev=n0 \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${PORT}-:8080" \
    -serial stdio -display none > "$LOG" 2>&1 &
qemu_pid=$!
cleanup() { kill "$qemu_pid" 2>/dev/null; wait "$qemu_pid" 2>/dev/null; rm -f "$LOG"; }
trap cleanup EXIT

# Wait for the guest to SAY it is listening rather than for the port to
# accept: the hypervisor's forwarded port accepts on the host side
# before the guest exists, so polling it would time the host.
for _ in $(seq 1 600); do
    grep -q 'serving on' "$LOG" && break
    kill -0 "$qemu_pid" 2>/dev/null || break
    sleep 0.02
done
if ! grep -q 'serving on' "$LOG"; then
    echo "FAIL: guest never listened. Console:" >&2
    sed 's/\r$//' "$LOG" >&2
    exit 1
fi

body="$(curl -sS --max-time 10 "http://127.0.0.1:${PORT}/healthz")"
answered_ns=$(date +%s%N)
elapsed_ms=$(( (answered_ns - start_ns) / 1000000 ))

check() {  # name expected-substring actual
    if printf '%s' "$3" | grep -q -- "$2"; then
        echo "PASS $1"
    else
        echo "FAIL $1: expected to find [$2] in [$3]"
        fails=$((fails + 1))
    fi
}

check "healthz"  "ok"                 "$body"
check "root"     "no operating"       "$(curl -sS --max-time 10 "http://127.0.0.1:${PORT}/")"
check "info"     '"pod":"smoke"'      "$(curl -sS --max-time 10 "http://127.0.0.1:${PORT}/info")"
check "metrics"  "nurl_requests_total" "$(curl -sS --max-time 10 "http://127.0.0.1:${PORT}/metrics")"
check "404"      "404"                "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:${PORT}/nope")"

# A second client, while a first one is holding a keep-alive connection
# open and saying nothing.
#
# This is not a load test — it is one idle connection, which is what a
# Kubernetes pod has before it has any users at all (a readiness probe
# and a liveness probe are two clients). A sequentially-serving loop
# answers the holder, waits out its 30 s idle timeout, and only then
# accepts anyone else; the kubelet times out and replaces the pod. That
# happened, in a real cluster, before this check existed.
exec 9<>"/dev/tcp/127.0.0.1/${PORT}" 2>/dev/null || { echo "FAIL concurrency: cannot open a holding connection"; fails=$((fails + 1)); }
if [ -e /proc/self/fd/9 ]; then
    printf 'GET /healthz HTTP/1.1\r\nHost: smoke\r\nConnection: keep-alive\r\n\r\n' >&9
    head -c 32 <&9 >/dev/null
    second="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:${PORT}/healthz")"
    exec 9<&-
    if [ "$second" = "200" ]; then
        echo "PASS concurrency (a held-open connection does not block the next client)"
    else
        echo "FAIL concurrency: second client got [$second] while one connection was held open"
        fails=$((fails + 1))
    fi
fi

if [ "$elapsed_ms" -le "$BUDGET_MS" ]; then
    echo "PASS cold start (${elapsed_ms} ms, budget ${BUDGET_MS} ms, accel ${ACCEL})"
else
    echo "FAIL cold start: ${elapsed_ms} ms > ${BUDGET_MS} ms budget (accel ${ACCEL})"
    fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo "smoke: all checks passed" || echo "smoke: ${fails} check(s) failed"
exit $(( fails == 0 ? 0 : 1 ))
