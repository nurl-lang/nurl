#!/usr/bin/env bash
# ============================================================
#  unikernel/build_unikernel.sh — build a NURL program into a bootable
#  x86_64 PVH kernel image.
#
#  Usage:  unikernel/build_unikernel.sh prog.nu [-o out.elf]
#              [--fs dir] [--out-dir dir]
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
#
#  Two invocations may run CONCURRENTLY. The split that makes that
#  true: everything program-independent (boot shim, nolibc, runtimes)
#  compiles ONCE into a cache directory under an flock, keyed by a
#  stamp that names every input and the flags — touch any of them and
#  the cache rebuilds; and everything program-dependent (the .ll, the
#  object, the initfs archive) is named after the program and lives in
#  --out-dir, so two builds never write the same path unless they ARE
#  the same build, in which case the ELFs come out byte-identical
#  (--build-id=none, and tar's inputs are the caller's own files).
#
#  Directories:
#    --out-dir DIR   per-program artifacts + the image (default
#                    $NURL_UNIKERNEL_OUT, else <repo>/build/unikernel)
#    cache           $NURL_UNIKERNEL_CACHE, else <out-dir>/cache.
#                    With both flags pointed elsewhere the repo is
#                    never written — it can be mounted read-only.
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT="$ROOT/unikernel/boot"
NOLIBC="$ROOT/unikernel/nolibc"
CC="${CC:-clang}"
SRC=""
OUT=""
FSDIR=""
OUTDIR="${NURL_UNIKERNEL_OUT:-$ROOT/build/unikernel}"

while [ $# -gt 0 ]; do
    case "$1" in
        -o) OUT="$2"; shift 2 ;;
        --fs) FSDIR="$2"; shift 2 ;;
        --out-dir) OUTDIR="$2"; shift 2 ;;
        *)  SRC="$1"; shift ;;
    esac
done
[ -n "$SRC" ] || {
    echo "usage: build_unikernel.sh prog.nu [-o out.elf] [--fs dir] [--out-dir dir]" >&2
    exit 2
}
[ -x "$ROOT/build/nurlc" ] || {
    echo "build_unikernel.sh: $ROOT/build/nurlc not found — run ./build.sh first" >&2
    exit 2
}
if [ -n "$FSDIR" ] && [ ! -d "$FSDIR" ]; then
    echo "build_unikernel.sh: --fs $FSDIR is not a directory" >&2
    exit 2
fi

CACHE="${NURL_UNIKERNEL_CACHE:-$OUTDIR/cache}"
mkdir -p "$OUTDIR" "$CACHE"
base="$(basename "${SRC%.nu}")"
OUT="${OUT:-$OUTDIR/$base.elf}"

KFLAGS="-ffreestanding -fno-stack-protector -fno-builtin -mno-red-zone
        -mcmodel=small -fno-pie -march=x86-64 -mno-sse4 -O2"

# ── the program-independent objects, once, under a lock ─────────
#
# The stamp is the answer to "is the cache current": it names every
# source these objects are built from, the flags and the compiler. If
# any input is newer than the stamp, or the recorded flags/CC differ,
# rebuild everything — the set is small enough that partial rebuilds
# are a source of skew, not a saving. The flock makes two concurrent
# first builds take turns instead of interleaving half-written objects.
cache_inputs() {
    printf '%s\n' \
        "$ROOT/stdlib/runtime_core.c" "$ROOT/stdlib/runtime_ctx.c" \
        "$ROOT/unikernel/runtime_bare.c" \
        "$NOLIBC"/string.c "$NOLIBC"/malloc.c "$NOLIBC"/stdio.c \
        "$NOLIBC"/dtoa.c "$NOLIBC"/math.c "$NOLIBC"/misc.c \
        "$NOLIBC"/setjmp_x86_64.S \
        "$BOOT"/platform_x86.c "$BOOT"/initfs.c "$BOOT"/pagealloc.c \
        "$BOOT"/nosys.c "$BOOT"/tls_guest.c "$BOOT"/boot.S \
        "$BOOT"/multiboot2.c "$BOOT"/con.c "$BOOT"/font8x16.c \
        "$BOOT"/mb2.h "$BOOT"/con.h "$BOOT"/font8x16.h \
        "${BASH_SOURCE[0]}"
}

cache_build() {
    $CC $KFLAGS -c "$ROOT/stdlib/runtime_core.c" -o "$CACHE/runtime_core.o"
    $CC $KFLAGS -c "$ROOT/stdlib/runtime_ctx.c"  -o "$CACHE/runtime_ctx.o"
    $CC $KFLAGS -c "$ROOT/unikernel/runtime_bare.c" -o "$CACHE/runtime_bare.o"
    for f in string malloc stdio dtoa math misc; do
        $CC $KFLAGS -c "$NOLIBC/$f.c" -o "$CACHE/nl_$f.o"
    done
    $CC $KFLAGS -c "$BOOT/platform_x86.c" -o "$CACHE/platform.o"
    $CC $KFLAGS -c "$BOOT/initfs.c"       -o "$CACHE/boot_initfs.o"
    $CC $KFLAGS -c "$BOOT/pagealloc.c"    -o "$CACHE/boot_pagealloc.o"
    $CC $KFLAGS -c "$BOOT/nosys.c"        -o "$CACHE/boot_nosys.o"
    $CC $KFLAGS -c "$BOOT/tls_guest.c"    -o "$CACHE/tls_guest.o"
    $CC $KFLAGS -c "$BOOT/multiboot2.c"   -o "$CACHE/boot_multiboot2.o"
    $CC $KFLAGS -c "$BOOT/con.c"          -o "$CACHE/boot_con.o"
    $CC $KFLAGS -c "$BOOT/font8x16.c"     -o "$CACHE/boot_font8x16.o"
    $CC -c "$BOOT/boot.S"                 -o "$CACHE/boot.o"
    $CC $KFLAGS -c "$NOLIBC/setjmp_x86_64.S" -o "$CACHE/nl_setjmp.o" 2>/dev/null \
        || $CC -c "$NOLIBC/setjmp_x86_64.S" -o "$CACHE/nl_setjmp.o"
}

stamp="$CACHE/stamp"
want_key="CC=$CC KFLAGS=$(echo $KFLAGS)"
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

# ── the program itself ──────────────────────────────────────────
#
# compile_nu.sh links in the NURL socket layer when `nm` says the
# program needs it — see that script for why that is a recompile
# rather than another object on the link line. It also owns stdlib
# resolution (NURL_STDLIB) and prints the compiler's message when the
# program does not compile.
NURL_NETDEV="$ROOT/unikernel/net/netdev_virtio.nu" \
    "$ROOT/unikernel/compile_nu.sh" "$SRC" "$OUTDIR/$base.ll" "$OUTDIR"
# compile_nu.sh leaves a hosted-flavoured object; recompile the IR with
# the kernel flags. `zig cc` drops -O for .ll inputs (#644) and plain
# clang needs the target flags spelled out for IR input too.
$CC $KFLAGS -c "$OUTDIR/$base.ll" -o "$OUTDIR/$base.o"

# The baked-in filesystem: a directory becomes a tar, and the tar
# becomes an object with two symbols around it. With no --fs the
# archive is empty rather than absent, so "no files" is a zero-length
# lookup instead of a conditional in every reader. Named after the
# program: two concurrent builds must not share a tar.
: > "$OUTDIR/$base.initfs.tar"
if [ -n "$FSDIR" ]; then
    tar cf "$OUTDIR/$base.initfs.tar" -C "$FSDIR" .
fi
( cd "$OUTDIR" && ld -r -b binary -o "$base.initfs_data.o" "$base.initfs.tar" )
# `ld -b binary` names its symbols after the path it was given; rename
# them to something a C file can declare without knowing that path.
sym="$(printf '%s' "$base.initfs.tar" | tr -c 'A-Za-z0-9' '_')"
objcopy \
    --redefine-sym "_binary_${sym}_start=nurl_initfs_start" \
    --redefine-sym "_binary_${sym}_end=nurl_initfs_end" \
    --redefine-sym "_binary_${sym}_size=nurl_initfs_size_sym" \
    "$OUTDIR/$base.initfs_data.o"

$CC -nostdlib -static -no-pie -Wl,-T,"$BOOT/link.ld" -Wl,--build-id=none \
    -o "$OUT" \
    "$CACHE/boot.o" "$OUTDIR/$base.o" \
    "$CACHE/runtime_core.o" "$CACHE/runtime_ctx.o" "$CACHE/runtime_bare.o" \
    "$CACHE/platform.o" "$CACHE/tls_guest.o" \
    "$CACHE/boot_initfs.o" "$CACHE/boot_pagealloc.o" "$CACHE/boot_nosys.o" \
    "$CACHE/boot_multiboot2.o" "$CACHE/boot_con.o" "$CACHE/boot_font8x16.o" \
    "$OUTDIR/$base.initfs_data.o" \
    "$CACHE"/nl_*.o

echo "built $OUT"
