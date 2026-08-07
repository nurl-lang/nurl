#!/usr/bin/env bash
# ============================================================
#  unikernel/run_qemu_arm64.sh — boot an AArch64 NURL unikernel image
#  and report what it printed and how it ended.
#
#  Usage:  run_qemu_arm64.sh image.elf [-t seconds] [-- extra qemu args]
#
#  Same contract as run_qemu.sh, one machine down: QEMU's `virt` board,
#  ELF loaded with -kernel, the device tree QEMU generates left at the
#  start of RAM for the guest to read. What differs from the x86 twin
#  and why:
#
#    - no `acpi=off`: virt publishes its virtio-mmio devices in the
#      DEVICE TREE, which the guest parses and turns into the same
#      `virtio_mmio.device=` entries the x86 guest reads off its
#      command line.
#    - `virtio-mmio.force-legacy=false` is still needed, and finding
#      that out cost a debugging round: the virt board defaults to the
#      LEGACY transport exactly as microvm does (the guest read
#      version=1 straight off the register). A legacy device is a
#      different protocol — 10-byte net header, PFN queue registers,
#      guest-endian fields — and hal/virtio.nu refuses one rather than
#      driving it wrong, so a default QEMU makes every device
#      disappear, correctly and confusingly.
#    - no `tsc_khz=`: this architecture's clock states its own
#      frequency in CNTFRQ_EL0. `wallclock=` stays — a wall clock is
#      the host's to state, on any machine.
#    - the program's argv still arrives as one `args="…"` key, in the
#      DTB's /chosen/bootargs rather than on a cmdline; -append is how
#      QEMU fills that node, so the spelling here is identical.
#
#  Exit status: the guest's, or 124 if the deadline passed with no
#  sentinel line.
# ============================================================
set -uo pipefail

QEMU="${QEMU_ARM64:-${QEMU:-qemu-system-aarch64}}"
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
[ -n "$IMG" ] || { echo "usage: run_qemu_arm64.sh image.elf [-t seconds]" >&2; exit 2; }
command -v "$QEMU" >/dev/null 2>&1 || { echo "run_qemu_arm64.sh: $QEMU not found" >&2; exit 3; }

# KVM only when the HOST is also aarch64 — an x86 developer machine
# runs this under TCG, which is slower and otherwise identical.
ACCEL=tcg
if [ -w /dev/kvm ] && [ "$(uname -m)" = "aarch64" ]; then ACCEL=kvm; fi
# `max` publishes the FEAT_RNG bit the guest's entropy check requires;
# a lesser CPU model makes the guest refuse to generate keys, which is
# the correct refusal and a confusing one to debug.
CPU="${NURL_ARM64_CPU:-max}"

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
grep -v '^\[nurl-exit\] ' "$out"

code=$(sed -n 's/^\[nurl-exit\] \([0-9]*\)$/\1/p' "$out" | tail -1)
rm -f "$out"
if [ -z "$code" ]; then
    echo "run_qemu_arm64.sh: no [nurl-exit] line — the guest did not finish (qemu $qemu_status)" >&2
    exit 124
fi
exit "$code"
