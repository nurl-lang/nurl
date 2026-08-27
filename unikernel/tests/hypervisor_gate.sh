#!/usr/bin/env bash
# ============================================================
#  unikernel/tests/hypervisor_gate.sh — the image is not a QEMU image.
#
#  QEMU is the hypervisor the guest gate boots under, and a target that
#  runs on exactly one hypervisor is a target with a dependency it does
#  not admit to. Firecracker and cloud-hypervisor both load an x86_64
#  kernel by **PVH direct boot** — they read the XEN_ELFNOTE_PHYS32_ENTRY
#  note out of the ELF and jump to the address in it — which is the
#  same note `boot/boot.S` emits and the same entry QEMU uses. So the
#  artifact needs no repackaging for either; what it needs is a check
#  that says so, and a boot when there is a machine to boot on.
#
#  Two levels, because they answer different questions:
#
#    STRUCTURE (always)   the note is present, is owned by "Xen", is
#                         type 18, carries a 4-byte descriptor, and the
#                         address in it is the ELF's own entry point
#                         inside a PT_LOAD segment. This is exactly what
#                         a PVH loader dispatches on, and it is checkable
#                         on any machine, with no hypervisor at all.
#    BOOT (when possible) cloud-hypervisor and/or firecracker actually
#                         start the image and it prints and exits. Both
#                         REQUIRE /dev/kvm — neither has an interpreter
#                         fallback — so without KVM this half SKIPS
#                         loudly rather than passing quietly.
#
#  Usage:  hypervisor_gate.sh [image.elf]
#          NURL_CLOUD_HYPERVISOR / NURL_FIRECRACKER name the binaries.
# ============================================================
set -uo pipefail

# Every check below parses readelf's English output with awk — and
# readelf localises ("Entry point" is something else on a Finnish
# desktop), which made this gate report an EMPTY entry address against
# a correct image. CI never sees it (C locale there), which is exactly
# why the fix belongs in the script, not in the environment.
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMG="${1:-$ROOT/build/unikernel/hello.elf}"
CH="${NURL_CLOUD_HYPERVISOR:-cloud-hypervisor}"
FC="${NURL_FIRECRACKER:-firecracker}"
fail=0
say() { echo "hypervisor_gate: $*"; }

if [ ! -f "$IMG" ]; then
    if [ -x "$ROOT/build/nurlc" ]; then
        "$ROOT/unikernel/build_unikernel.sh" "$ROOT/compiler/tests/hello.nu" >/dev/null 2>&1 \
            || { say "SKIP (cannot build a test image)"; exit 0; }
    else
        say "SKIP (no build/nurlc — run ./build.sh first)"; exit 0
    fi
fi

# ── which machine is this image for? ─────────────────────────────
#
# PVH is an x86 protocol. On AArch64 both Firecracker and
# cloud-hypervisor take a PE-format `Image` (the shape a Linux
# arm64 kernel is packaged in), not the ELF QEMU's virt board loads
# with -kernel — so there is no note to check and no boot to attempt,
# and the honest answer is to say which artifact this is and stop.
# Wrapping the ELF in a PE header is a packaging step this target
# could grow; claiming portability it does not have is not.
machine=$(readelf -hW "$IMG" | awk -F: '/Machine:/ {print $2}' | sed 's/^ *//')
case "$machine" in
    *AArch64*)
        # PVH is x86-only. What Firecracker and cloud-hypervisor take on
        # THIS architecture is a flat `Image` — the format a Linux arm64
        # kernel ships in — and boot_arm64.S puts its 64-byte header at
        # offset 0 of the same build. So the question here is the same
        # question, asked of the other container: is the header what a
        # loader dispatches on?
        img="${IMG%.elf}.Image"
        if [ ! -f "$img" ]; then
            objc="${NURL_OBJCOPY:-llvm-objcopy}"
            command -v "$objc" >/dev/null 2>&1 || {
                say "SKIP AArch64 Image check (no llvm-objcopy to flatten the ELF)"
                exit 0
            }
            img="$(mktemp)"
            "$objc" -O binary "$IMG" "$img" || { say "FAIL: could not flatten the ELF"; exit 1; }
        fi
        hdr=$(od -A n -t x1 -N 64 "$img" | tr -d ' \n')
        # magic "ARM\x64" at offset 0x38, little-endian in the file as
        # the four ASCII bytes 41 52 4d 64.
        if [ "${hdr:112:8}" != "41524d64" ]; then
            say "FAIL: no ARM64 image magic at offset 0x38 — Firecracker and"
            say "      cloud-hypervisor have nothing to dispatch on"
            exit 1
        fi
        # code0 must be a real instruction: a b/bl (top byte 0x14/0x94 in
        # little-endian byte order → the 4th byte of the word). A zeroed
        # code0 is what a header written as pure data looks like, and a
        # loader jumping to offset 0 would execute it.
        c0b3="${hdr:6:2}"
        case "$c0b3" in
            14|94) ;;
            *) say "FAIL: code0 is not a branch (byte 3 = 0x$c0b3) — a loader"
               say "      that jumps to offset 0 would not reach the boot code"
               fail=1 ;;
        esac
        # text_offset (0x08) must match where the image is LINKED inside
        # its 2 MiB-aligned region: this image is not position-independent
        # and the field is what makes a loader put it where its absolute
        # addresses already point.
        toff=$(python3 -c "import sys;h=sys.argv[1];print(int.from_bytes(bytes.fromhex(h[16:32]),'little'))" "$hdr" 2>/dev/null || echo -1)
        # The image's BASE, not its entry point: the header describes
        # where byte 0 of the image goes, and the entry sits 64 bytes
        # further on because the header itself is those 64 bytes. The
        # first check written here used the entry and reported a 64-byte
        # discrepancy as a defect — a gate being precise about which
        # address a field means.
        base=$(readelf -lW "$IMG" | awk '/LOAD/ {print $3; exit}')
        # Offset within the gigabyte the image is linked into: RAM on
        # this board starts at a gigabyte boundary, so this is the
        # distance from DRAM start that the loader must reproduce.
        region=$(( $((base)) - ($((base)) & ~0x3FFFFFFF) ))
        if [ "$toff" -lt 0 ]; then
            say "FAIL: could not read text_offset"
            fail=1
        elif [ "$toff" != "$region" ]; then
            say "FAIL: text_offset is $toff but the image is linked $region bytes"
            say "      into its region — a loader would place it where its own"
            say "      absolute addresses do not point"
            fail=1
        fi
        # image_size must cover the file, .bss included.
        isize=$(python3 -c "import sys;h=sys.argv[1];print(int.from_bytes(bytes.fromhex(h[32:48]),'little'))" "$hdr" 2>/dev/null || echo 0)
        fsize=$(stat -c %s "$img")
        if [ "$isize" -lt "$fsize" ]; then
            say "FAIL: image_size ($isize) is smaller than the image ($fsize)"
            fail=1
        fi
        [ "$fail" = 0 ] && say "AArch64 Image header OK — magic, code0 is a branch, text_offset $toff, image_size $isize"
        say "     (Firecracker and cloud-hypervisor take this container on"
        say "     this architecture; booting them needs an AArch64 HOST —"
        say "     neither emulates, so there is nothing here to run them on.)"
        [ "$fail" = 0 ] && say "verified: AArch64 Image header (no AArch64 host to boot it under)"
        exit $fail
        ;;
esac

# ── the note, read with the tools every toolchain ships ─────────
#
# `readelf -n` prints the owner, the descriptor size and the descriptor
# bytes; the type is printed as a number when unrecognised, which is
# what "Xen" type 18 is to binutils. Parsed rather than eyeballed so
# the gate fails when the note stops being what a loader expects.
notes=$(readelf -nW "$IMG" 2>/dev/null)
if ! printf '%s' "$notes" | grep -q "\.note\.Xen"; then
    say "FAIL: no .note.Xen section — a PVH loader (Firecracker,"
    say "      cloud-hypervisor, QEMU -kernel) has nothing to dispatch on"
    exit 1
fi
if ! printf '%s' "$notes" | grep -qE "Xen +0x0*4"; then
    say "FAIL: the Xen note's descriptor is not 4 bytes (a 32-bit entry address)"
    fail=1
fi
if ! printf '%s' "$notes" | grep -qiE "0x0*12|XEN_ELFNOTE_PHYS32_ENTRY"; then
    say "FAIL: the Xen note is not type 18 (XEN_ELFNOTE_PHYS32_ENTRY)"
    fail=1
fi

# The address in the descriptor must be the ELF's entry point: the two
# are set independently (the note by boot.S, the entry by the linker
# script) and a loader that uses one while a developer tests the other
# is a boot that works under QEMU and not under Firecracker.
desc=$(printf '%s' "$notes" | grep -A2 "Xen" | grep -oE "description data: [0-9a-f ]+" | head -1 |
       sed 's/description data: //')
if [ -n "$desc" ]; then
    # little-endian bytes → an address
    note_addr=$(printf '%s' "$desc" | awk '{printf "0x%s%s%s%s", $4, $3, $2, $1}')
    entry=$(readelf -hW "$IMG" | awk '/Entry point/ {print $4}')
    if [ "$((note_addr))" != "$((entry))" ]; then
        say "FAIL: the PVH note says $note_addr but the ELF entry is $entry"
        say "      — QEMU uses the note, and a mismatch boots two different addresses"
        fail=1
    fi
fi
[ "$fail" = 0 ] && say "PVH note OK — type 18, 4-byte descriptor, address == ELF entry"

# ── the boot, when there is a machine to boot on ────────────────
#
# USABILITY, not existence. A GitHub runner HAS /dev/kvm and denies the
# job user access to it (group kvm), so `[ -e ]` said "boot it" and the
# gate then reported a permission error as a defect in the image. What
# the gate is asking is "can this process open KVM", and the honest
# answer to "no" is a skip with the reason — an environment the gate
# cannot run in is not a failing artifact.
if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    if [ -e /dev/kvm ]; then
        say "SKIP boot: /dev/kvm exists but this user cannot open it"
        say "     (add the user to the 'kvm' group, or chmod it in CI)."
    else
        say "SKIP boot: no /dev/kvm — Firecracker and cloud-hypervisor have"
        say "     no interpreter fallback, so there is nothing to run them on."
    fi
    say "     (QEMU covers the boot path under TCG; this gate covers the"
    say "     artifact's portability to the other two.)"
    [ "$fail" = 0 ] && say "verified: PVH note (no usable KVM here to boot it under)"
    exit $fail
fi

boot_ch() {
    command -v "$CH" >/dev/null 2>&1 || { skipped="$skipped cloud-hypervisor"; return 0; }
    out=$(timeout -k 5s 60s "$CH" \
        --kernel "$IMG" \
        --cmdline "tsc_khz=1000000 wallclock=$(date +%s)" \
        --cpus boot=1 --memory size=64M \
        --console off --serial tty 2>&1)
    # `case`, not `printf | grep -q`: grep exits the moment it matches,
    # printf then gets EPIPE, and under `set -o pipefail` the pipeline
    # reports THAT — so a guest that booted perfectly was reported as a
    # failed boot, with its own successful output printed underneath.
    # A glob match needs no pipe and no subprocess.
    case "$out" in
      *"[nurl-exit] 0"*)
        say "PASS cloud-hypervisor booted the unchanged image"
        booted="$booted cloud-hypervisor"
        ;;
      *"Failed to set Cpuid"*|*"VcpuConfiguration"*|*"SetSupportedCpusFailed"*)
        # The host declined to give the VM a vCPU. This says nothing
        # about the image: the failure is before any guest instruction
        # runs, and the structural PVH check above — the part that IS
        # about our artifact — already passed.
        #
        # The gate's KVM test above asks whether this process can OPEN
        # /dev/kvm, which a runner can allow while still refusing to
        # host a VM (nested virtualisation off, KVM_GET_SUPPORTED_CPUID
        # unavailable). That is the same "present is not usable" lesson
        # the readability check above was written for, one step further
        # along, and it turned main red for an environment property.
        #
        # An image defect looks different and is still caught: the VM
        # starts and the guest never prints its exit line, or the loader
        # complains about the ELF or the PVH note.
        say "SKIP boot: cloud-hypervisor could not configure a vCPU on this host"
        say "     (KVM opens but will not host a VM — nested virt off?)"
        skipped="$skipped cloud-hypervisor"
        ;;
      *)
        say "FAIL cloud-hypervisor"
        printf '%s\n' "$out" | head -6 | sed 's/^/     /' || true
        fail=1
        ;;
    esac
}

boot_fc() {
    command -v "$FC" >/dev/null 2>&1 || { skipped="$skipped firecracker"; return 0; }
    # Firecracker is API-driven; the one-shot form takes a JSON config.
    # `drives` is required even when empty from v1.16 on — without it a
    # modern Firecracker refuses the config with "missing field `drives`"
    # and the gate reports a boot failure against a perfectly good image.
    # Nothing here noticed, because the gate SKIPS when firecracker is
    # not installed and CI does not install it.
    cfg=$(mktemp); log=$(mktemp)
    cat > "$cfg" <<EOF
{
  "boot-source": {
    "kernel_image_path": "$IMG",
    "boot_args": "tsc_khz=1000000 wallclock=$(date +%s)"
  },
  "drives": [],
  "machine-config": { "vcpu_count": 1, "mem_size_mib": 64 }
}
EOF
    out=$(timeout -k 5s 60s "$FC" --no-api --config-file "$cfg" 2>&1)
    rm -f "$cfg" "$log"
    case "$out" in
      *"[nurl-exit] 0"*)
        say "PASS firecracker booted the unchanged image"
        booted="$booted firecracker"
        ;;
      *"Failed to set Cpuid"*|*"VcpuConfiguration"*|*"SetSupportedCpusFailed"*|*"Cannot create Vcpu"*)
        # Same host-declined-a-vCPU case as cloud-hypervisor above, in
        # the other loader's wording. Both are given the exclusion, or
        # the next runner without nested virt fails on whichever one it
        # happens to have installed.
        say "SKIP boot: firecracker could not configure a vCPU on this host"
        skipped="$skipped firecracker"
        ;;
      *)
        say "FAIL firecracker"
        printf '%s\n' "$out" | head -6 | sed 's/^/     /' || true
        fail=1
        ;;
    esac
}

booted=""
skipped=""
boot_ch
boot_fc
# One last line naming what actually ran. The unit-gate runner shows a
# step's LAST line, and "SKIP firecracker (not installed)" is the least
# informative thing this gate can say — the fact worth seeing is that a
# hypervisor other than QEMU booted the image.
if [ "$fail" = 0 ]; then
    if [ -n "$booted" ]; then
        say "verified: PVH note + booted under$booted${skipped:+ (skipped:$skipped)}"
    else
        say "verified: PVH note (no other hypervisor available to boot it)"
    fi
fi
exit $fail
