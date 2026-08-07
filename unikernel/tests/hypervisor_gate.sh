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
        say "AArch64 image — PVH is x86-only, so there is no note to check."
        say "     QEMU virt loads this ELF directly (the AArch64 guest gate"
        say "     boots it). Firecracker and cloud-hypervisor want a"
        say "     PE-format Image on this architecture: a packaging step"
        say "     this target has not taken, not a property it has."
        exit 0
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
    cfg=$(mktemp); log=$(mktemp)
    cat > "$cfg" <<EOF
{
  "boot-source": {
    "kernel_image_path": "$IMG",
    "boot_args": "tsc_khz=1000000 wallclock=$(date +%s)"
  },
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
