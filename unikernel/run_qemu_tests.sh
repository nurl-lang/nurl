#!/usr/bin/env bash
# ============================================================
#  unikernel/run_qemu_tests.sh — run corpus tests INSIDE the guest and
#  compare against the same goldens the hosted runner uses.
#
#  Usage:  unikernel/run_qemu_tests.sh [name …]     (default: the list below)
#
#  The list is short on purpose. The nolibc corpus runner already
#  proves 449 tests against these goldens with no libc; what a QEMU run
#  adds is the bottom edge — the boot path, the UART, the memory map
#  the hypervisor reported, the TSC — so the tests here are chosen to
#  exercise those and nothing else twice:
#
#    hello        the whole print path, and an exit code that gets out
#    vec_basic    the allocator against the guest's memory map
#    float_format the software float formatter, on a machine whose SSE
#                 state the boot stub enabled by hand
#    net_socket   the sans-IO stack, the socket layer and the loopback,
#                 all of it, on bare metal
#    net_tcpstack the connection table, likewise
#    async_*      the cooperative scheduler on stacks whose guard pages
#                 are real page-table entries, and — async_sleep — the
#                 TSC, which is the one clock this machine has
#
#  Requires qemu-system-x86_64; skips (exit 0) with a message when it
#  is absent, because a developer without QEMU should still be able to
#  run the rest of the gates.
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$ROOT/compiler/tests"
QEMU="${QEMU:-qemu-system-x86_64}"

command -v "$QEMU" >/dev/null 2>&1 || {
    echo "run_qemu_tests.sh: $QEMU not found — skipping the guest gate"
    exit 0
}

names=("$@")
[ ${#names[@]} -gt 0 ] || names=(hello vec_basic float_format
                                 net_socket net_tcpstack
                                 async_basic async_chan async_mn async_sleep)

fails=0
for name in "${names[@]}"; do
    golden="$TESTS/outputs/$name.txt"
    [ -f "$golden" ] || { echo "SKIP $name (no golden)"; continue; }
    if ! "$ROOT/unikernel/build_unikernel.sh" "$TESTS/$name.nu" >/dev/null 2>&1; then
        echo "FAIL $name (build)"; fails=$((fails + 1)); continue
    fi
    want_exit=$(sed -n 's/^EXIT //p' "$golden" | head -1)
    want_out=$(sed -n '/^OUTPUT$/,$p' "$golden" | tail -n +2)
    got_out=$("$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/$name.elf" -t 60 2>&1)
    got_exit=$?
    if [ "$got_out" = "$want_out" ] && [ "$got_exit" = "$want_exit" ]; then
        echo "PASS $name"
    else
        echo "FAIL $name (exit $got_exit, want ${want_exit:-?})"
        diff <(printf '%s\n' "$want_out") <(printf '%s\n' "$got_out") | head -6 | sed 's/^/     /'
        fails=$((fails + 1))
    fi
done

# ── the demos, which only exist in the guest ────────────────────
# A corpus test cannot cover these: they talk to hardware, so there is
# no hosted golden to compare against and no host on which to produce
# one. Each demo carries its own expected output beside it, and the
# QEMU arguments it needs are named here — a virtio-net device for the
# one that goes looking for devices.
demos=0
if [ $# -eq 0 ]; then
    for demo in devices netdev dhcp; do
        src="$ROOT/unikernel/demos/$demo.nu"
        exp="$ROOT/unikernel/demos/$demo.expected"
        [ -f "$src" ] && [ -f "$exp" ] || continue
        demos=$((demos + 1))
        if ! "$ROOT/unikernel/build_unikernel.sh" "$src" >/dev/null 2>&1; then
            echo "FAIL $demo (build)"; fails=$((fails + 1)); continue
        fi
        got=$("$ROOT/unikernel/run_qemu.sh" "$ROOT/build/unikernel/$demo.elf" -t 60 -- \
              -netdev user,id=n0 -device virtio-net-device,netdev=n0 2>&1)
        if [ "$got" = "$(cat "$exp")" ]; then
            echo "PASS $demo (guest-only demo)"
        else
            echo "FAIL $demo"
            diff "$exp" <(printf '%s\n' "$got") | head -6 | sed 's/^/     /'
            fails=$((fails + 1))
        fi
    done
fi

echo "── QEMU guest run: $((${#names[@]} + demos - fails))/$((${#names[@]} + demos)) ──"
[ "$fails" -eq 0 ]
