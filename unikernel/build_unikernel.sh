#!/usr/bin/env bash
# ============================================================
#  unikernel/build_unikernel.sh — build a NURL program into a bootable
#  x86_64 PVH kernel image.
#
#  Usage:  unikernel/build_unikernel.sh prog.nu [-o out.elf]
#
#  Same NURL, same runtime_core.c, same runtime_bare.c and the same
#  nolibc as the Linux -nostdlib build. Exactly three files differ, and
#  they are the ones that talk to the machine:
#
#    boot/boot.S           PVH entry → long mode → SSE → stack → kmain
#    boot/platform_x86.c   UART, memory map, TSC, RDRAND, shutdown
#    boot/tls_guest.c      the thread pointer, without an auxv to read
#
#  replacing nolibc/start_x86_64.S, nolibc/syscall_linux.c and
#  nolibc/tls_linux.c respectively. That is the whole target: the Linux
#  freestanding build is not a toy, it is this program with a different
#  bottom edge, which is what makes testing it there worth anything.
#
#  -mno-red-zone everywhere: the red zone is 128 bytes below rsp that a
#  leaf function may use, and anything that pushes a frame without
#  moving rsp first — an exception handler — silently corrupts it.
#  v1 takes no device interrupts, but an exception handler is still an
#  exception handler, and the flag costs nothing.
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT="$ROOT/unikernel/boot"
NOLIBC="$ROOT/unikernel/nolibc"
OUTDIR="${NURL_UNIKERNEL_OUT:-$ROOT/build/unikernel}"
CC="${CC:-clang}"
SRC=""
OUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        -o) OUT="$2"; shift 2 ;;
        *)  SRC="$1"; shift ;;
    esac
done
[ -n "$SRC" ] || { echo "usage: build_unikernel.sh prog.nu [-o out.elf]" >&2; exit 2; }

mkdir -p "$OUTDIR"
base="$(basename "${SRC%.nu}")"
OUT="${OUT:-$OUTDIR/$base.elf}"

KFLAGS="-ffreestanding -fno-stack-protector -fno-builtin -mno-red-zone
        -mcmodel=small -fno-pie -march=x86-64 -mno-sse4 -O2"

# The NURL program, plus the socket layer if it uses one. Same script as
# the Linux freestanding build — the decision is measured there, and
# duplicating it here is how the two would drift.
NURL_NETDEV="$ROOT/unikernel/net/netdev_virtio.nu" \
    "$ROOT/unikernel/compile_nu.sh" "$SRC" "$OUTDIR/$base.ll" "$OUTDIR"
# compile_nu.sh leaves a hosted-flavoured object; recompile the IR with
# the kernel flags. `zig cc` drops -O for .ll inputs (#644) and plain
# clang needs the target flags spelled out for IR input too.
$CC $KFLAGS -c "$OUTDIR/$base.ll" -o "$OUTDIR/$base.o"

$CC $KFLAGS -c "$ROOT/stdlib/runtime_core.c" -o "$OUTDIR/runtime_core.o"
$CC $KFLAGS -c "$ROOT/stdlib/runtime_ctx.c"  -o "$OUTDIR/runtime_ctx.o"
$CC $KFLAGS -c "$ROOT/unikernel/runtime_bare.c" -o "$OUTDIR/runtime_bare.o"

for f in string malloc stdio dtoa math misc; do
    $CC $KFLAGS -c "$NOLIBC/$f.c" -o "$OUTDIR/nl_$f.o"
done
$CC $KFLAGS -c "$BOOT/platform_x86.c" -o "$OUTDIR/platform.o"
$CC $KFLAGS -c "$BOOT/tls_guest.c"    -o "$OUTDIR/tls_guest.o"
$CC -c "$BOOT/boot.S"                 -o "$OUTDIR/boot.o"
$CC $KFLAGS -c "$NOLIBC/setjmp_x86_64.S" -o "$OUTDIR/nl_setjmp.o" 2>/dev/null \
    || $CC -c "$NOLIBC/setjmp_x86_64.S" -o "$OUTDIR/nl_setjmp.o"

$CC -nostdlib -static -no-pie -Wl,-T,"$BOOT/link.ld" -Wl,--build-id=none \
    -o "$OUT" \
    "$OUTDIR/boot.o" "$OUTDIR/$base.o" \
    "$OUTDIR/runtime_core.o" "$OUTDIR/runtime_ctx.o" "$OUTDIR/runtime_bare.o" \
    "$OUTDIR/platform.o" "$OUTDIR/tls_guest.o" \
    "$OUTDIR"/nl_*.o

echo "built $OUT"
