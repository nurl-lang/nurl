#!/usr/bin/env bash
# ============================================================
#  unikernel/build_bootable_image.sh — wrap a NURL unikernel in a
#  bootloader so it boots on a real PC, off a USB stick.
#
#  Usage:  unikernel/build_bootable_image.sh prog.elf [-o out.img]
#              [--args "a b c"] [--append "k=v ..."] [--title NAME]
#
#  Then, on the machine that is to boot it:
#
#      sudo dd if=out.img of=/dev/sdX bs=4M conv=fsync status=progress
#
#  ── why there is a bootloader here at all ──────────────────────
#
#  The ELF `build_unikernel.sh` produces already boots on QEMU,
#  Firecracker and cloud-hypervisor with nothing in between: they read
#  its PVH note and jump straight in. A PC's firmware does not. A
#  legacy BIOS reads a 512-byte boot sector; UEFI reads a PE executable
#  off a FAT partition; neither has ever heard of a PVH note. Something
#  has to stand between the firmware and the kernel, and writing that
#  something — a bootloader with a FAT driver and a UEFI stub — is a
#  second project, not a step in this one.
#
#  So the SAME ELF gains a second door. `boot/boot.S` carries a
#  Multiboot2 header beside its PVH note, GRUB is what reads it, and
#  this script is what puts GRUB on a disk. One artifact, four loaders,
#  no repackaging — the property U7 established for the hypervisors,
#  extended to iron.
#
#  ── why not grub-mkrescue ──────────────────────────────────────
#
#  It is the obvious tool and it does exactly this, but its `-d` takes
#  ONE platform directory and it derives nothing: given a directory it
#  builds for that platform and silently omits the other. There is no
#  spelling of the flag that produces a BIOS and a UEFI image in one
#  run from module trees that are not under the compiled-in
#  /usr/lib/grub. That would make an image whose UEFI half is missing
#  the normal outcome of not having root — and the failure shows up as
#  a machine that does nothing, on someone else's desk.
#
#  So the two boot images are built separately with `grub-mkstandalone`
#  and assembled with `xorriso` here. Both take an explicit module
#  directory, so this runs unprivileged, in CI, and in a container.
#
#  ── the shape of what comes out ────────────────────────────────
#
#  A hybrid image: an El Torito ISO that is ALSO a valid MBR/GPT disk
#  carrying a FAT EFI system partition. A legacy BIOS boots it from the
#  MBR, a UEFI firmware finds EFI/BOOT/BOOTX64.EFI on the ESP, and one
#  `dd` to a USB stick serves both.
#
#  The kernel and the GRUB config are EMBEDDED IN THE MEMDISK of each
#  boot image rather than read off the filesystem. That is what removes
#  iso9660, FAT and partition-table drivers from the boot path
#  entirely: by the time GRUB runs `multiboot2`, everything it needs is
#  already in memory. A copy of the kernel is left on the ISO as well,
#  where it is readable by anyone who mounts the stick to see what is
#  on it, and is not what boots.
#
#  ── overrides, for a machine whose tools are elsewhere ─────────
#
#    NURL_GRUB_LIB   a directory holding the i386-pc/ and x86_64-efi/
#                    module directories (default /usr/lib/grub). BOTH
#                    must be there: an image that boots under only one
#                    firmware is not something this script will produce
#                    without saying so.
# ============================================================
set -euo pipefail

MKSTANDALONE="${NURL_GRUB_MKSTANDALONE:-grub-mkstandalone}"
GRUBLIB="${NURL_GRUB_LIB:-/usr/lib/grub}"

ELF=""
OUT=""
ARGS=""
APPEND=""
TITLE="NURL unikernel"

while [ $# -gt 0 ]; do
    case "$1" in
        -o)       OUT="$2"; shift 2 ;;
        --args)   ARGS="$2"; shift 2 ;;
        --append) APPEND="$2"; shift 2 ;;
        --title)  TITLE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,70p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//'
            exit 0 ;;
        *)        ELF="$1"; shift ;;
    esac
done

[ -n "$ELF" ] || {
    echo "usage: build_bootable_image.sh prog.elf [-o out.img] [--args \"a b\"] [--append \"k=v\"] [--title NAME]" >&2
    exit 2
}
[ -f "$ELF" ] || { echo "build_bootable_image.sh: $ELF does not exist" >&2; exit 2; }
OUT="${OUT:-${ELF%.elf}.img}"

# ── the tools, each named with what installs it ─────────────────
#
# Every one of these missing has the same symptom — an image that does
# not boot, or boots under only one of the two firmwares — and none of
# them announces itself. Check first, name the package.
need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "build_bootable_image.sh: $1 not found — install $2" >&2
        echo "    Debian/Ubuntu:  apt install $3" >&2
        exit 2
    }
}
need "$MKSTANDALONE" "GRUB's build tools" "grub-common"
need xorriso  "xorriso"  "xorriso"
need mformat  "mtools"   "mtools"
need mcopy    "mtools"   "mtools"
need mmd      "mtools"   "mtools"

missing=""
[ -d "$GRUBLIB/i386-pc" ]    || missing="$missing
    $GRUBLIB/i386-pc      (BIOS boot)  — apt install grub-pc-bin"
[ -d "$GRUBLIB/x86_64-efi" ] || missing="$missing
    $GRUBLIB/x86_64-efi   (UEFI boot)  — apt install grub-efi-amd64-bin"
if [ -n "$missing" ]; then
    echo "build_bootable_image.sh: missing GRUB module directories:$missing" >&2
    echo >&2
    echo "  Both are required. Which firmware a given PC offers is not something" >&2
    echo "  this build can know, so an image is only finished when it boots under" >&2
    echo "  either. Set NURL_GRUB_LIB to a directory holding both to override." >&2
    exit 2
fi
[ -f "$GRUBLIB/i386-pc/boot_hybrid.img" ] || {
    echo "build_bootable_image.sh: $GRUBLIB/i386-pc/boot_hybrid.img is absent" >&2
    echo "  — it is the MBR that makes the ISO also a disk, i.e. the thing that" >&2
    echo "  makes 'dd to a USB stick' work at all." >&2
    exit 2
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# ── the GRUB configuration ──────────────────────────────────────
#
# The kernel command line is everything after the path, and the guest
# reads two kinds of thing out of it: `args="…"` becomes argv (quoted,
# because the line is not the program's alone — see build_argv in
# boot/platform_x86.c), and bare key=value pairs are for the machine.
#
# timeout=0 boots immediately: an appliance that waits for a keypress
# is an appliance that does not come back up after a power cut.
cmdline=""
[ -n "$APPEND" ] && cmdline="$cmdline $APPEND"
[ -n "$ARGS" ]   && cmdline="$cmdline args=\"$ARGS\""

# `insmod all_video` is the line without which a UEFI boot has no
# screen. GRUB honours the kernel's framebuffer request by calling
# grub_video_set_mode, and that fails with "no suitable video mode
# found" when no video driver has been loaded — having the module
# available in the image is not the same as having loaded it, and
# nothing loads a video driver on demand. The guest then boots
# correctly, prints to a serial port nobody is holding, and looks dead.
# Measured: without this line, exactly that, under OVMF.
cat > "$STAGE/grub.cfg" <<EOF
set timeout=0
set default=0

insmod all_video

menuentry "$TITLE" {
    multiboot2 /boot/nurl.elf$cmdline
    boot
}
EOF

# ── the two boot images ─────────────────────────────────────────
#
# --install-modules is not an optimisation. The BIOS core image has a
# hard ceiling of 0x78000 bytes and the default ("all") is three times
# that, so the unfiltered build FAILS for i386-pc while succeeding for
# UEFI — one platform, silently, again.
#
# all_video is the one non-obvious entry: under UEFI it brings in
# efi_gop, which is what lets GRUB set a mode and hand the guest a
# framebuffer. Without it a UEFI boot has nowhere to draw and the
# machine runs correctly with a blank screen.
MODULES="multiboot2 normal configfile boot echo test minicmd sleep all_video gfxterm"

standalone() {   # $1 = grub format, $2 = module dir, $3 = output
    "$MKSTANDALONE" -O "$1" -d "$GRUBLIB/$2" \
        --install-modules="$MODULES" --fonts= --themes= --locales= \
        -o "$3" \
        "boot/grub/grub.cfg=$STAGE/grub.cfg" \
        "boot/nurl.elf=$ELF"
}

standalone i386-pc-eltorito i386-pc    "$STAGE/eltorito.img"
standalone x86_64-efi       x86_64-efi "$STAGE/bootx64.efi"

# ── the EFI system partition ────────────────────────────────────
#
# A FAT filesystem holding one file at the path UEFI looks for when it
# is booting a removable device it knows nothing else about. Sized from
# the payload with slack and rounded to a multiple of 32 KiB, because
# mformat lays out a FAT by geometry and a size that is not a round
# number of clusters is one it declines.
esp_kb=$(( ($(wc -c < "$STAGE/bootx64.efi") / 1024 + 128) / 32 * 32 + 32 ))
mkdir -p "$STAGE/iso/boot/grub/i386-pc"
dd if=/dev/zero of="$STAGE/iso/boot/grub/efi.img" bs=1024 count="$esp_kb" status=none
mformat -i "$STAGE/iso/boot/grub/efi.img" ::
mmd     -i "$STAGE/iso/boot/grub/efi.img" ::/EFI ::/EFI/BOOT
mcopy   -i "$STAGE/iso/boot/grub/efi.img" "$STAGE/bootx64.efi" ::/EFI/BOOT/BOOTX64.EFI

cp "$STAGE/eltorito.img" "$STAGE/iso/boot/grub/i386-pc/eltorito.img"
cp "$ELF"                "$STAGE/iso/boot/nurl.elf"

# ── one disk, two boot records ──────────────────────────────────
#
# -isohybrid-mbr writes GRUB's MBR into the first 512 bytes, which is
# what a BIOS reads off a USB stick. -eltorito-alt-boot starts a second
# boot entry, and -isohybrid-gpt-basdat publishes the FAT image as a
# GPT partition so UEFI firmware can find it. Take either away and the
# image still boots — under one firmware, on the bench, and not on the
# machine it was made for.
xorriso -as mkisofs \
    -o "$OUT" \
    -volid NURL \
    --grub2-mbr "$GRUBLIB/i386-pc/boot_hybrid.img" \
    -partition_offset 16 \
    -b boot/grub/i386-pc/eltorito.img \
        -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
        -no-emul-boot -isohybrid-gpt-basdat \
    "$STAGE/iso" 2>&1 | grep -viE '^(xorriso|libisofs|Drive|Media|ISO image|Written|Writing|Added)' || true

[ -s "$OUT" ] || { echo "build_bootable_image.sh: xorriso produced nothing" >&2; exit 1; }

# ── prove both halves are in there ──────────────────────────────
#
# The checks above say the INPUTS were present. This says the output
# has them, which is a different claim and the one that matters: the
# El Torito catalogue lists one entry per firmware, and a missing
# platform here is exactly the silent single-firmware image this whole
# script is arranged to avoid.
report="$(xorriso -indev "$OUT" -report_el_torito plain 2>/dev/null || true)"
bios=0; uefi=0
case "$report" in *"boot img :   1  BIOS"*) bios=1 ;; esac
case "$report" in *"UEFI"*) uefi=1 ;; esac
if [ "$bios" = 0 ] || [ "$uefi" = 0 ]; then
    echo "build_bootable_image.sh: $OUT boots under BIOS=$bios UEFI=$uefi — expected both" >&2
    echo "$report" >&2
    exit 1
fi

size="$(wc -c < "$OUT")"
echo "built $OUT ($((size / 1024)) KiB) — El Torito records for BIOS and UEFI both present"
echo
echo "  write it to a USB stick with:"
echo "      sudo dd if=$OUT of=/dev/sdX bs=4M conv=fsync status=progress"
echo "  where /dev/sdX is the WHOLE DISK, not a partition — everything on it is lost."
