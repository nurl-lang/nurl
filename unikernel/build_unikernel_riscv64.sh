#!/usr/bin/env bash
# ============================================================
#  unikernel/build_unikernel_riscv64.sh — build a NURL program into a
#  bootable RV64 kernel image for QEMU's `virt` machine.
#
#  Usage:  build_unikernel_riscv64.sh prog.nu [-o out.elf]
#              [--fs dir] [--out-dir dir]
#
#  Everything above the bottom edge is the SAME code the x86_64 image
#  runs — runtime_core.c, runtime_bare.c, nolibc, the NURL program.
#  Exactly four files differ, and they are the ones that talk to the
#  machine:
#
#    boot/boot_riscv64.S       S-mode entry, hart parking, trap vector, FP, stacks
#    boot/platform_riscv64.c  16550 UART, Sv39 MMU, rdtime, SBI shutdown
#                             (and an honest refusal on entropy: this
#                             machine has no seed CSR)
#    boot/tls_guest_riscv64.c   the thread pointer (variant I, measured)
#    nolibc/setjmp_riscv64.S  panic/recover's callee-saved set
#
#  which is the whole point of the arrangement: a THIRD architecture is
#  a bottom edge, not a port of the system — and the device-tree walk
#  the AArch64 port wrote is now shared (boot/fdt.c) rather than
#  copied, because a copy is where two machines start disagreeing
#  about what the same tree says.
#
#  The cross toolchain is zig cc (already in the ecosystem's install and
#  in the playground image) targeting riscv64-freestanding-none. Same
#  --out-dir / cache contract as the x86_64 script, and the cache is
#  keyed separately so both architectures can be built side by side.
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT="$ROOT/unikernel/boot"
NOLIBC="$ROOT/unikernel/nolibc"
ZIG="${NURL_ZIG:-${ZIG:-zig}}"
command -v "$ZIG" >/dev/null 2>&1 || ZIG="$HOME/.nurl/zig/zig"
SRC=""
OUT=""
FSDIR=""
OUTDIR="${NURL_UNIKERNEL_OUT:-$ROOT/build/unikernel-riscv64}"

while [ $# -gt 0 ]; do
    case "$1" in
        -o) OUT="$2"; shift 2 ;;
        --fs) FSDIR="$2"; shift 2 ;;
        --out-dir) OUTDIR="$2"; shift 2 ;;
        *)  SRC="$1"; shift ;;
    esac
done
[ -n "$SRC" ] || {
    echo "usage: build_unikernel_riscv64.sh prog.nu [-o out.elf] [--fs dir] [--out-dir dir]" >&2
    exit 2
}
[ -x "$ROOT/build/nurlc" ] || {
    echo "build_unikernel_riscv64.sh: $ROOT/build/nurlc not found — run ./build.sh first" >&2
    exit 2
}
command -v "$ZIG" >/dev/null 2>&1 || {
    echo "build_unikernel_riscv64.sh: no zig on PATH and none at ~/.nurl/zig/zig — set NURL_ZIG" >&2
    exit 2
}
if [ -n "$FSDIR" ] && [ ! -d "$FSDIR" ]; then
    echo "build_unikernel_riscv64.sh: --fs $FSDIR is not a directory" >&2
    exit 2
fi

# A cache of its OWN, one per architecture: the
# object filenames are identical across architectures (runtime_core.o,
# nl_string.o, boot.o…), so one directory shared by both builds means
# an x86 link can pick up RV64 objects — or, with the stamp saving
# it, both builds rebuilding everything on every alternation. The arch
# belongs in the cache's identity, not only in its stamp.
CACHE="${NURL_UNIKERNEL_CACHE_RISCV64:-$OUTDIR/cache}"
mkdir -p "$OUTDIR" "$CACHE"
base="$(basename "${SRC%.nu}")"
OUT="${OUT:-$OUTDIR/$base.elf}"

# Two triples, deliberately. Compiling uses riscv64-linux-musl so the
# C files can #include <stdio.h> and friends — runtime_core.c does, and
# nolibc supplies the DEFINITIONS while some libc's headers supply the
# declarations. That is exactly what the x86_64 build does implicitly by
# using the host clang (host headers, nolibc objects); saying it out
# loud is the difference between the two scripts, not a difference in
# the model. Linking uses -nostdlib, so not one byte of musl is in the
# image — `nm` on the result proves it, and the gate checks.
TARGET=riscv64-linux-musl
# -mgeneral-regs-only is NOT set: the runtime uses floating point, and
# the boot code un-traps FP/SIMD before C runs. What IS set is the same
# freestanding discipline as x86 — no stack protector, no builtins that
# assume a libc, small code model to match the linker script's single
# 2 MiB-aligned load address.
KFLAGS="-target $TARGET -ffreestanding -fno-stack-protector -fno-builtin
        -mcmodel=small -fno-pie -O2"

cache_inputs() {
    printf '%s\n' \
        "$ROOT/stdlib/runtime_core.c" "$ROOT/stdlib/runtime_ctx.c" \
        "$ROOT/unikernel/runtime_bare.c" \
        "$NOLIBC"/string.c "$NOLIBC"/malloc.c "$NOLIBC"/stdio.c \
        "$NOLIBC"/dtoa.c "$NOLIBC"/math.c "$NOLIBC"/misc.c \
        "$NOLIBC"/setjmp_riscv64.S \
        "$BOOT"/platform_riscv64.c "$BOOT"/initfs.c "$BOOT"/pagealloc.c \
        "$BOOT"/nosys.c "$BOOT"/fdt.c "$BOOT"/cmdenv.c "$BOOT"/virtio_rng.c \
        "$BOOT"/tls_guest_riscv64.c "$BOOT"/boot_riscv64.S \
        "$ROOT/stdlib/cuda_stubs.c" "$ROOT/stdlib/nvrtc_stubs.c" \
        "${BASH_SOURCE[0]}"
}

cache_build() {
    # shellcheck disable=SC2086
    $ZIG cc $KFLAGS -c "$ROOT/stdlib/runtime_core.c" -o "$CACHE/runtime_core.o"
    $ZIG cc $KFLAGS -c "$ROOT/stdlib/runtime_ctx.c"  -o "$CACHE/runtime_ctx.o"
    $ZIG cc $KFLAGS -c "$ROOT/unikernel/runtime_bare.c" -o "$CACHE/runtime_bare.o"
    for f in string malloc stdio dtoa math misc; do
        $ZIG cc $KFLAGS -c "$NOLIBC/$f.c" -o "$CACHE/nl_$f.o"
    done
    $ZIG cc $KFLAGS -c "$BOOT/platform_riscv64.c"  -o "$CACHE/platform.o"
    $ZIG cc $KFLAGS -c "$BOOT/initfs.c"          -o "$CACHE/boot_initfs.o"
    $ZIG cc $KFLAGS -c "$BOOT/pagealloc.c"       -o "$CACHE/boot_pagealloc.o"
    $ZIG cc $KFLAGS -c "$BOOT/nosys.c"           -o "$CACHE/boot_nosys.o"
    # CUDA/NVRTC driver-API stubs — the same no-GPU answers nurl.sh links
    # on a host with no NVIDIA driver (see build_unikernel.sh).
    $ZIG cc $KFLAGS -c "$ROOT/stdlib/cuda_stubs.c"  -o "$CACHE/cuda_stubs.o"
    $ZIG cc $KFLAGS -c "$ROOT/stdlib/nvrtc_stubs.c" -o "$CACHE/nvrtc_stubs.o"
    $ZIG cc $KFLAGS -c "$BOOT/fdt.c"             -o "$CACHE/boot_fdt.o"
    $ZIG cc $KFLAGS -c "$BOOT/cmdenv.c"          -o "$CACHE/boot_cmdenv.o"
    $ZIG cc $KFLAGS -c "$BOOT/virtio_rng.c"      -o "$CACHE/boot_virtio_rng.o"
    $ZIG cc $KFLAGS -c "$BOOT/tls_guest_riscv64.c" -o "$CACHE/tls_guest.o"
    $ZIG cc $KFLAGS -c "$BOOT/boot_riscv64.S"      -o "$CACHE/boot.o"
    $ZIG cc $KFLAGS -c "$NOLIBC/setjmp_riscv64.S" -o "$CACHE/nl_setjmp.o"
}

stamp="$CACHE/stamp"
want_key="ZIG=$ZIG KFLAGS=$(echo $KFLAGS)"
(
    flock 9
    fresh=1
    if [ ! -f "$stamp" ] || [ "$(head -1 "$stamp" 2>/dev/null)" != "$want_key" ]; then
        fresh=0
    else
        while IFS= read -r f; do
            [ "$f" -nt "$stamp" ] && { fresh=0; break; }
        done < <(cache_inputs)
    fi
    if [ "$fresh" = 0 ]; then
        cache_build
        printf '%s\n' "$want_key" > "$stamp"
    fi
) 9>"$CACHE/.lock"

# The program. compile_nu.sh links in the NURL socket layer when `nm`
# says the program needs it; NURL_NM points it at a cross-capable nm so
# the measurement is made on THIS architecture's object.
NURL_NETDEV="$ROOT/unikernel/net/netdev_virtio.nu" \
NURL_TARGET_CC="$ZIG cc -target $TARGET" \
    "$ROOT/unikernel/compile_nu.sh" "$SRC" "$OUTDIR/$base.ll" "$OUTDIR"
# shellcheck disable=SC2086
$ZIG cc $KFLAGS -Wno-override-module -c "$OUTDIR/$base.ll" -o "$OUTDIR/$base.o"

: > "$OUTDIR/$base.initfs.tar"
if [ -n "$FSDIR" ]; then
    tar cf "$OUTDIR/$base.initfs.tar" -C "$FSDIR" .
fi
# The archive becomes an object with two symbols around it. `ld -r -b
# binary` is x86-only output; the portable spelling is a tiny .S that
# .incbin's the file, which also lets the symbols be named directly
# instead of renamed afterwards.
cat > "$OUTDIR/$base.initfs.S" <<EOF
    .section .rodata
    .globl nurl_initfs_start
    .globl nurl_initfs_end
    .align 8
nurl_initfs_start:
    .incbin "$OUTDIR/$base.initfs.tar"
nurl_initfs_end:
    .section .note.GNU-stack, "", %progbits
EOF
# shellcheck disable=SC2086
$ZIG cc $KFLAGS -c "$OUTDIR/$base.initfs.S" -o "$OUTDIR/$base.initfs_data.o"

# shellcheck disable=SC2086
# -Wl,-e: zig cc hands the linker its own default entry (_start) after
# our script, and lld's "cannot find entry symbol _start" left the ELF
# header's entry point at ZERO — an image QEMU would jump to address 0
# for. The script's ENTRY() is still there and still right; this makes
# the command line agree with it.
# max-page-size=4096: lld's riscv64 default is 64 KiB, which pads every
# LOAD segment's file offset to a boundary this machine has no use for —
# the guest's own page tables use the 4 KiB granule. It cost 300 KB of
# padding in a 500 KB image. -S strips the debug info zig cc emits by
# default (another 80 KB), which a boot image cannot use: the fault
# handler reports registers, and the ELF a developer debugs is the one
# in the build directory, not the one the hypervisor loads.
$ZIG cc -target $TARGET -nostdlib -static -Wl,-T,"$BOOT/link_riscv64.ld" \
    -Wl,-e,_riscv_start -Wl,--build-id=none \
    -Wl,-z,max-page-size=4096 -Wl,-S \
    -o "$OUT" \
    "$CACHE/boot.o" "$OUTDIR/$base.o" \
    "$CACHE/runtime_core.o" "$CACHE/runtime_ctx.o" "$CACHE/runtime_bare.o" \
    "$CACHE/platform.o" "$CACHE/tls_guest.o" \
    "$CACHE/boot_initfs.o" "$CACHE/boot_pagealloc.o" "$CACHE/boot_nosys.o" \
    "$CACHE/boot_fdt.o" "$CACHE/boot_virtio_rng.o" "$CACHE/boot_cmdenv.o" \
    "$CACHE/cuda_stubs.o" "$CACHE/nvrtc_stubs.o" \
    "$OUTDIR/$base.initfs_data.o" \
    "$CACHE"/nl_*.o

echo "built $OUT"
