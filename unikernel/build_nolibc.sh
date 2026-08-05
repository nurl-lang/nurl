#!/usr/bin/env bash
# ============================================================
#  unikernel/build_nolibc.sh — build a NURL program against nolibc,
#  with glibc nowhere in the link line.
#
#  This is the A3 nolibc gate, and it is a LINK-level test on purpose:
#  the freestanding libc subset is exercised by a real NURL binary
#  built with -nostdlib, so a missing or wrong symbol is a link error
#  or a failed run, not something discovered at boot in Track B.
#
#  Usage:  unikernel/build_nolibc.sh prog.nu [-o out]
#
#  What it links:
#    prog.ll            — nurlc output
#    runtime_core.o     — the bootstrap half of the runtime, compiled
#                         on its own (no runtime_ffi: a nolibc program
#                         has no sockets, processes or pthreads yet)
#    nolibc/*.o         — this directory
#
#  -fno-builtin on the string sources is load-bearing: clang recognises
#  a byte-copy loop and rewrites it into a call to memcpy, which inside
#  memcpy is infinite recursion.
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOLIBC="$ROOT/unikernel/nolibc"
OUTDIR="${NURL_NOLIBC_OUT:-$ROOT/build/nolibc}"
CC="${CC:-clang}"
SRC=""
OUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        -o) OUT="$2"; shift 2 ;;
        *)  SRC="$1"; shift ;;
    esac
done
[ -n "$SRC" ] || { echo "usage: build_nolibc.sh prog.nu [-o out]" >&2; exit 2; }

mkdir -p "$OUTDIR"
base="$(basename "${SRC%.nu}")"
OUT="${OUT:-$OUTDIR/$base}"

# 1. NURL -> LLVM IR (the ordinary compiler; nothing target-specific yet)
"$ROOT/build/nurlc" "$SRC" > "$OUTDIR/$base.ll"

# 2. IR -> object. `zig cc` drops -O for .ll inputs (#644) and so does
#    plain clang for some flag combinations, so compile IR to an object
#    in its own step with the flags spelled out.
"$CC" -O2 -c "$OUTDIR/$base.ll" -o "$OUTDIR/$base.o"

# 3. The runtime, minus runtime_ffi.c. Three objects where the hosted
#    build has one, because the aggregator stdlib/runtime.c exists to
#    concatenate exactly these and runtime_ffi.c — and runtime_ffi.c is
#    the one a freestanding target cannot have.
#      runtime_core.c — the bootstrap half, byte-for-byte the hosted one
#      runtime_ctx.c  — the stackful switch, likewise shared verbatim
#      runtime_bare.c — the cooperative twin of runtime_ffi.c
"$CC" -O2 -c "$ROOT/stdlib/runtime_core.c" -o "$OUTDIR/runtime_core.o"
"$CC" -O2 -c "$ROOT/stdlib/runtime_ctx.c"  -o "$OUTDIR/runtime_ctx.o"
"$CC" -O2 -ffreestanding -fno-stack-protector \
      -c "$ROOT/unikernel/runtime_bare.c" -o "$OUTDIR/runtime_bare.o"

# 4. nolibc itself.
for f in string malloc stdio dtoa misc syscall_linux tls_linux; do
    "$CC" -O2 -ffreestanding -fno-builtin -fno-stack-protector \
          -c "$NOLIBC/$f.c" -o "$OUTDIR/nl_$f.o"
done
for f in start_x86_64 setjmp_x86_64; do
    "$CC" -c "$NOLIBC/$f.S" -o "$OUTDIR/nl_$f.o"
done

# 5. Link with no libc, no crt, no dynamic loader.
"$CC" -nostdlib -static -no-pie -o "$OUT" \
      "$OUTDIR/$base.o" "$OUTDIR/runtime_core.o" "$OUTDIR/runtime_ctx.o" \
      "$OUTDIR/runtime_bare.o" "$OUTDIR"/nl_*.o

echo "built $OUT"
if command -v ldd >/dev/null 2>&1; then
    if ldd "$OUT" 2>&1 | grep -qv "not a dynamic executable"; then
        echo "note: $(ldd "$OUT" 2>&1 | head -2)"
    fi
fi
