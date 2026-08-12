#!/usr/bin/env bash
# ============================================================
#  unikernel/tests/baremetal_gate.sh — the image also boots on iron.
#
#  `hypervisor_gate.sh` covers the PVH note, which is how QEMU,
#  Firecracker and cloud-hypervisor find the kernel. No PC firmware
#  reads that note. A BIOS reads a boot sector and UEFI reads a PE
#  binary off a FAT partition, so booting real hardware goes through a
#  bootloader, and what the bootloader dispatches on is the Multiboot2
#  header in `boot/boot.S`.
#
#  Everything this checks fails the same way when it breaks: a machine
#  that sits there. There is no console output to read, because the
#  failure is upstream of the guest ever running — which is why the
#  checks are structural and mechanical rather than "boot it and see".
#
#  Three levels, each answering a different question and each degrading
#  to a LOUD skip rather than a quiet pass:
#
#    HEADER (always)      the Multiboot2 header is where a bootloader
#                         looks (first 32 KiB of the FILE, 8-byte
#                         aligned), its checksum sums to zero, its
#                         entry-address tag points at `_mb2_start` and
#                         not at the ELF entry, and the framebuffer tag
#                         is present. Needs no tools but readelf.
#    IMAGE  (with GRUB)   the hybrid image builds and carries El Torito
#                         records for BIOS *and* UEFI. A single-firmware
#                         image is the failure this is here to catch:
#                         it boots on the bench and not on the target.
#    BOOT   (with QEMU)   SeaBIOS boots it and the guest says so, in its
#                         own words, on the serial port.
#
#  Usage:  baremetal_gate.sh [image.elf]
#          QEMU / NURL_GRUB_LIB override the tools.
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMG="${1:-}"
QEMU="${QEMU:-qemu-system-x86_64}"
GRUBLIB="${NURL_GRUB_LIB:-/usr/lib/grub}"
fail=0
say() { echo "baremetal_gate: $*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -z "$IMG" ]; then
    [ -x "$ROOT/build/nurlc" ] || { say "SKIP (no build/nurlc — run ./build.sh first)"; exit 0; }
    "$ROOT/unikernel/build_unikernel.sh" "$ROOT/compiler/tests/hello.nu" \
        -o "$TMP/hello.elf" --out-dir "$TMP" >/dev/null 2>&1 \
        || { say "SKIP (cannot build a test image)"; exit 0; }
    IMG="$TMP/hello.elf"
fi
[ -f "$IMG" ] || { say "FAIL: $IMG does not exist"; exit 1; }

machine=$(LC_ALL=C readelf -hW "$IMG" | awk -F: '/Machine:/ {print $2}' | sed 's/^ *//')
case "$machine" in
    *X86-64*|*x86-64*) : ;;
    *)  say "SKIP: $machine — Multiboot2 is an x86 protocol, and the other"
        say "     ports boot their own way (AArch64 takes a flat Image, RISC-V"
        say "     is handed over by OpenSBI). Nothing to check here."
        exit 0 ;;
esac

# ── level 1: the header ─────────────────────────────────────────
#
# Done in Python against the raw file rather than with readelf, because
# every property here is about the BYTES AT A FILE OFFSET — that is
# literally what a bootloader scans — and a section-header view would
# confirm a layout the loader never consults.
mb2start=$(LC_ALL=C nm "$IMG" 2>/dev/null | awk '/ _mb2_start$/ {print $1}')
pvhstart=$(LC_ALL=C nm "$IMG" 2>/dev/null | awk '/ _pvh_start$/ {print $1}')
if [ -z "$mb2start" ]; then
    say "FAIL: the image has no _mb2_start — there is no Multiboot2 entry point"
    exit 1
fi

python3 - "$IMG" "$mb2start" "$pvhstart" <<'PY'
import struct, sys

path, mb2start, pvhstart = sys.argv[1], int(sys.argv[2], 16), int(sys.argv[3] or "0", 16)
blob = open(path, "rb").read()
bad = []

off = blob.find(struct.pack("<I", 0xE85250D6))
if off < 0:
    print("baremetal_gate: FAIL: no Multiboot2 magic anywhere in the file")
    sys.exit(1)

# A bootloader searches only the first 32 KiB and only on 8-byte
# boundaries. Both are properties of the LINK, so both can drift
# without anything else noticing.
if off % 8:
    bad.append(f"the header is at offset {off}, which is not 8-byte aligned")
if off >= 32768:
    bad.append(f"the header is at offset {off}, past the 32 KiB a loader scans")

magic, arch, length, csum = struct.unpack_from("<4I", blob, off)
if arch != 0:
    bad.append(f"architecture is {arch}, expected 0 (32-bit protected mode)")
if (magic + arch + length + csum) & 0xFFFFFFFF:
    bad.append("the checksum does not sum to zero — the header is invalid")

tags, p = {}, off + 16
while p < off + length:
    t, _flags, sz = struct.unpack_from("<HHI", blob, p)
    if sz < 8:
        bad.append(f"tag type {t} declares size {sz}")
        break
    tags[t] = (p, sz)
    if t == 0:
        break
    p += (sz + 7) & ~7

if 3 not in tags:
    # Without it a loader jumps to the ELF entry, which is _pvh_start,
    # which reads %ebx as an hvm_start_info pointer and panics about a
    # boot that was perfectly good.
    bad.append("no entry-address tag (type 3) — GRUB would jump to the PVH entry")
else:
    p, _ = tags[3]
    entry = struct.unpack_from("<I", blob, p + 8)[0]
    if entry != mb2start:
        bad.append(f"entry-address tag points at {entry:#x}, but _mb2_start is {mb2start:#x}")
    if pvhstart and entry == pvhstart:
        bad.append("entry-address tag points at _pvh_start — the two entries are not interchangeable")

if 5 not in tags:
    # UEFI has no VGA text memory. With no framebuffer handed over there
    # is nowhere on the screen to write, and the guest runs correctly
    # while looking dead.
    bad.append("no framebuffer tag (type 5) — a UEFI boot would have no screen")

if 0 not in tags:
    bad.append("no end tag (type 0) — the tag list is unterminated")

for b in bad:
    print("baremetal_gate: FAIL:", b)
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fail=1

if [ "$fail" = 0 ]; then
    say "header OK — Multiboot2 magic 8-byte aligned in the first 32 KiB,"
    say "        checksum zero, entry tag on _mb2_start, framebuffer requested"
fi

# ── level 2: the image ──────────────────────────────────────────
if [ ! -d "$GRUBLIB/i386-pc" ] || [ ! -d "$GRUBLIB/x86_64-efi" ] \
   || ! command -v grub-mkstandalone >/dev/null 2>&1 \
   || ! command -v xorriso >/dev/null 2>&1 \
   || ! command -v mformat >/dev/null 2>&1; then
    say "SKIP image+boot: needs grub-mkstandalone, xorriso, mtools and both"
    say "     $GRUBLIB/{i386-pc,x86_64-efi}. The header above is checked"
    say "     everywhere; this half needs the bootloader's own build tools."
    [ "$fail" = 0 ] && say "verified: the Multiboot2 header (no GRUB tooling here to package it)"
    exit $fail
fi

if ! "$ROOT/unikernel/build_bootable_image.sh" "$IMG" -o "$TMP/boot.img" \
        --args "gate" > "$TMP/build.log" 2>&1; then
    say "FAIL: build_bootable_image.sh could not package the image"
    sed 's/^/    /' "$TMP/build.log"
    exit 1
fi
say "image OK — hybrid disk with El Torito records for BIOS and UEFI"

# ── level 3: the boot ───────────────────────────────────────────
if ! command -v "$QEMU" >/dev/null 2>&1 && [ ! -x "$QEMU" ]; then
    say "SKIP boot: no $QEMU"
    [ "$fail" = 0 ] && say "verified: the header and the packaging (nothing here to boot it on)"
    exit $fail
fi

# A real firmware, a real bootloader, a real disk — the whole path a USB
# stick takes, minus the stick. `-no-reboot` so a triple fault ends the
# run instead of looping the gate.
timeout 120 "$QEMU" -m 256 \
    -drive "file=$TMP/boot.img,format=raw,if=ide,media=disk" \
    -serial "file:$TMP/serial.log" \
    -display none -no-reboot > "$TMP/qemu.log" 2>&1
rc=$?

out="$(cat "$TMP/serial.log" 2>/dev/null)"
case "$out" in
    # The guest's own words. `case` rather than `grep -q`: under
    # `set -o pipefail` a successful match makes grep exit while the
    # producer is still writing, the producer gets EPIPE, and a
    # SUCCESSFUL boot is reported as a failure with the guest's output
    # printed as the evidence against it.
    *"[nurl-exit] 0"*)
        say "boot OK — SeaBIOS -> GRUB -> multiboot2 -> the guest ran and exited 0" ;;
    *)
        say "FAIL: booted through GRUB but the guest never reported a clean exit (qemu rc=$rc)"
        say "  --- serial ---"
        printf '%s\n' "$out" | sed 's/^/    /'
        say "  --- qemu ---"
        sed 's/^/    /' "$TMP/qemu.log"
        fail=1 ;;
esac

[ "$fail" = 0 ] && say "verified: header, hybrid packaging, and a real BIOS boot"
exit $fail
