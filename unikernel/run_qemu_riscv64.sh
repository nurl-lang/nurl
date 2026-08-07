#!/usr/bin/env bash
# ============================================================
#  unikernel/run_qemu_riscv64.sh — boot an RV64 NURL unikernel image
#  and report what it printed and how it ended.
#
#  Usage:  run_qemu_riscv64.sh image.elf [-t seconds] [-- extra qemu args]
#
#  Same contract as run_qemu.sh, a third machine down: QEMU's `virt`
#  board, ELF loaded with -kernel, OpenSBI as the firmware underneath.
#  What differs and why:
#
#    - OpenSBI runs first and hands the kernel S-mode with a0 = hart id
#      and a1 = the device tree. There is nothing for the host to say
#      about the handover, so this script says less than either twin.
#    - the same `virtio-mmio.force-legacy=false` as both other boards:
#      virt is legacy by default here too, and the guest refuses a
#      legacy device rather than driving it wrong.
#    - no clock flag at all: `rdtime` ticks at the rate the tree states
#      (10 MHz on virt). `wallclock=` stays, as on every machine — a
#      wall clock is the host's to state.
#    - the program's argv still arrives as one `args="…"` key, in the
#      DTB's /chosen/bootargs, which -append fills.
#
#  Exit status: the guest's, or 124 if the deadline passed with no
#  sentinel line.
# ============================================================
set -uo pipefail

QEMU="${QEMU_RISCV64:-${QEMU:-qemu-system-riscv64}}"
TIMEOUT=20
IMG=""
read -r -a EXTRA <<< "${QEMU_ARGS:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        -t) TIMEOUT="$2"; shift 2 ;;
        --) shift; EXTRA+=("$@"); break ;;
        *)  IMG="$1"; shift ;;
    esac
done
[ -n "$IMG" ] || { echo "usage: run_qemu_riscv64.sh image.elf [-t seconds]" >&2; exit 2; }
command -v "$QEMU" >/dev/null 2>&1 || { echo "run_qemu_riscv64.sh: $QEMU not found" >&2; exit 3; }

# KVM only when the HOST is also riscv64 — an x86 developer machine
# runs this under TCG, which is slower and otherwise identical.
ACCEL=tcg
if [ -w /dev/kvm ] && [ "$(uname -m)" = "riscv64" ]; then ACCEL=kvm; fi
# `rv64` is the board's own default and what a user would run. There is
# no CPU model that gives this guest entropy — the Zkr seed CSR is
# optional and QEMU does not implement it — so a program that generates
# keys panics here by design, and no flag changes that.
CPU="${NURL_RISCV64_CPU:-rv64}"

out="$(mktemp)"
timeout -k 5s "${TIMEOUT}s" "$QEMU" \
    -M virt \
    -accel "$ACCEL" -cpu "$CPU" -m 256 \
    -nodefaults -no-reboot -no-user-config \
    -global virtio-mmio.force-legacy=false \
    -kernel "$IMG" -append "wallclock=$(date +%s) ${NURL_APPEND:-}" \
    -serial stdio -display none \
    ${EXTRA[@]+"${EXTRA[@]}"} > "$out" 2>&1
qemu_status=$?

sed -i 's/\r$//' "$out"
# The firmware's banner is not the program's output. OpenSBI prints
# before the kernel runs, on the same UART; the guest marks its own
# first byte with `[nurl-boot]` and everything up to and including that
# line is the machine's, not the program's. `-a`: the banner contains
# bytes that make grep call the stream binary otherwise, and then it
# prints "binary file matches" instead of the output.
if grep -aq '^\[nurl-boot\]$' "$out"; then
    sed -i '1,/^\[nurl-boot\]$/d' "$out"
fi
grep -av '^\[nurl-exit\] ' "$out"

code=$(sed -n 's/^\[nurl-exit\] \([0-9]*\)$/\1/p' "$out" | tail -1)
rm -f "$out"
if [ -z "$code" ]; then
    echo "run_qemu_riscv64.sh: no [nurl-exit] line — the guest did not finish (qemu $qemu_status)" >&2
    exit 124
fi
exit "$code"
