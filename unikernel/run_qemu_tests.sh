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
[ ${#names[@]} -gt 0 ] || names=(hello vec_basic float_format net_socket net_tcpstack)

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

echo "── QEMU guest run: $((${#names[@]} - fails))/${#names[@]} ──"
[ "$fails" -eq 0 ]
