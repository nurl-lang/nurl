#!/usr/bin/env bash
# ============================================================
#  unikernel/run_qemu.sh — boot a NURL unikernel image and report what
#  it printed and how it ended.
#
#  Usage:  unikernel/run_qemu.sh image.elf [-t seconds] [-- extra qemu args]
#
#  QEMU microvm with acpi=off: virtio-mmio devices are published on the
#  kernel command line instead of in an ACPI table, which is a cmdline
#  parse rather than an AML interpreter (plan B0). PVH direct boot, so
#  there is no BIOS and no bootloader in the picture at all.
#
#  The guest's exit code comes back on the SERIAL LINE, as
#  `[nurl-exit] N`. That is the primary protocol because it is the only
#  one both hypervisors can carry: Firecracker cannot hand a guest exit
#  code back at all. isa-debug-exit is a QEMU-side cross-check and is
#  attached when the machine supports it.
#
#  Exit status: the guest's, or 124 if the deadline passed with no
#  sentinel line (a hang looks like a hang, not like a pass).
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QEMU="${QEMU:-qemu-system-x86_64}"
TIMEOUT=20
IMG=""
# Anything the host needs to say to QEMU that the guest has no opinion
# about — a -L for a QEMU installed somewhere unusual, an accel
# override. Kept out of the script so the invocation below stays the
# one the CI job and a developer both read.
read -r -a EXTRA <<< "${QEMU_ARGS:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        -t) TIMEOUT="$2"; shift 2 ;;
        --) shift; EXTRA+=("$@"); break ;;
        *)  IMG="$1"; shift ;;
    esac
done
[ -n "$IMG" ] || { echo "usage: run_qemu.sh image.elf [-t seconds]" >&2; exit 2; }
command -v "$QEMU" >/dev/null 2>&1 || { echo "run_qemu.sh: $QEMU not found" >&2; exit 3; }

# QEMU's virtio-mmio defaults to force-legacy=true, and a legacy device
# is a different protocol: 10-byte net header, PFN-based queue
# registers, guest-endian fields. hal/virtio.nu refuses one rather than
# driving it wrong, so the guest reports "no device" against a default
# QEMU — correctly, and confusingly. The flag is the host's half of
# that decision.
#
# The clock, stated rather than guessed. Under KVM the guest reads the
# TSC frequency from CPUID leaf 0x40000010 and ignores what we say here;
# under TCG no leaf reports one, QEMU's virtual TSC ticks at 1 GHz, and
# a guest that refuses to invent a frequency (correctly) would have no
# clock at all. `wallclock` is the boot epoch — a functionality input,
# not a security control: the host already controls the whole image.
#
# KVM when it is there, TCG when it is not. CI runners have no /dev/kvm,
# and the difference is speed, not behaviour — except for the TSC
# frequency, which under TCG no leaf reports, so the guest panics on the
# first request for the time rather than inventing one. `-cpu max`
# publishes the invtsc/RDRAND bits the guest checks for.
ACCEL=tcg
[ -w /dev/kvm ] && ACCEL=kvm

out="$(mktemp)"
timeout -k 5s "${TIMEOUT}s" "$QEMU" \
    -M microvm,acpi=off,rtc=off \
    -accel "$ACCEL" -cpu max -m 256 \
    -nodefaults -no-reboot -no-user-config \
    -global virtio-mmio.force-legacy=false \
    -kernel "$IMG" -append "tsc_khz=${NURL_TSC_KHZ:-1000000} wallclock=$(date +%s)" \
    -serial stdio -display none \
    ${EXTRA[@]+"${EXTRA[@]}"} > "$out" 2>&1
qemu_status=$?

# \r comes from the UART's CRLF, not from the program.
sed -i 's/\r$//' "$out"
grep -v '^\[nurl-exit\] ' "$out"

code=$(sed -n 's/^\[nurl-exit\] \([0-9]*\)$/\1/p' "$out" | tail -1)
rm -f "$out"
if [ -z "$code" ]; then
    echo "run_qemu.sh: no [nurl-exit] line — the guest did not finish (qemu $qemu_status)" >&2
    exit 124
fi
exit "$code"
