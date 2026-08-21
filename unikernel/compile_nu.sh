#!/usr/bin/env bash
# ============================================================
#  unikernel/compile_nu.sh — compile one NURL program for a
#  freestanding link, pulling in the NURL socket layer if (and only if)
#  the program actually needs it, and the disk layer when the build
#  asked for one.
#
#  Usage:  compile_nu.sh <src.nu> <out.ll> <workdir>
#
#  A hosted program gets its sockets from stdlib/runtime_ffi.c, which is
#  the one file a freestanding target cannot have. unikernel/net/
#  sockets.nu defines the same symbols in NURL over the sans-IO stack,
#  and nurlc lets a definition supersede an FFI declaration — so the
#  program is unchanged and only the link line differs.
#
#  It cannot simply be a separate object: NURL compiles a program and
#  its imports into ONE module, so a separately-built shim would carry
#  its own copy of every stdlib function it uses and the link would die
#  of duplicate definitions. It has to be part of the same compilation,
#  which is what the generated root file below does — it imports the
#  program and the shim, and `main` comes from the program.
#
#  Whether it is needed is MEASURED, not listed: the program is compiled
#  once on its own, its undefined symbols are read out of the object
#  with `nm`, and the set the shim defines is grepped out of the shim's
#  own source. Neither side is a list in this file — a hand-kept list of
#  names is what gated the whole live surface of the runtime out of CI,
#  twice.
#
#  Exit status is nurlc's / clang's. The object is left at
#  <workdir>/<name>.o next to the .ll.
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM="$ROOT/unikernel/net/sockets.nu"
# The compiler for the OBJECT this script produces. NURL_TARGET_CC lets
# a cross build pass a whole command ("zig cc -target aarch64-…"): the
# nm measurement below has to be made on the object for the TARGET,
# because "which symbols are undefined" is an answer about the machine
# the program will run on.
CC="${NURL_TARGET_CC:-${CC:-clang}}"
# nm reads whatever the CC above produced. llvm-nm handles every target
# clang can emit; plain nm on a foreign object says "file format not
# recognized" and the socket layer would then be linked in never or
# always, silently.
NM="${NURL_NM:-}"
if [ -z "$NM" ]; then
    if command -v llvm-nm >/dev/null 2>&1; then NM="llvm-nm"
    elif command -v llvm-nm-16 >/dev/null 2>&1; then NM="llvm-nm-16"
    else NM="nm"; fi
fi

# The stdlib is HERE, and this script knows it. Without this a package
# build (cwd = the package root, see below) resolved `stdlib/…` imports
# against the package directory and died with "cannot open
# stdlib/core/string.nu" — and worse, died SILENTLY, because the error
# went to compile.err and nothing printed it. Callers may still point
# NURL_STDLIB somewhere else; the default is the repo this script is in.
export NURL_STDLIB="${NURL_STDLIB:-$ROOT}"

# A failed step says WHY, on stderr, prefixed with whose voice it is.
# The err files stay in the workdir for tooling; the human gets the
# message at the moment of failure. This script cost its author twenty
# minutes of "exit 3, no output" — never again.
#
# NURL_COMPILE_QUIET=1 restores the old silence for the one caller that
# wants it: the corpus runner compiles a thousand tests and CLASSIFIES
# failures by exit code — for it the noise would drown the report.
fail() { # fail <exit-code> <errfile> <what>
    if [ -z "${NURL_COMPILE_QUIET:-}" ]; then
        echo "compile_nu.sh: $3 failed for $name:" >&2
        sed 's/^/  /' "$2" >&2
    fi
    exit "$1"
}

SRC="$1"; OUT_LL="$2"; WORK="$3"
# Absolute, before anything cds anywhere: the workdir below is chosen
# per source, and a relative path stops meaning the same thing the
# moment it changes.
SRC="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
case "$OUT_LL" in /*) ;; *) OUT_LL="$PWD/$OUT_LL" ;; esac
case "$WORK" in /*) ;; *) WORK="$PWD/$WORK" ;; esac
name="$(basename "${OUT_LL%.ll}")"
OBJ="$WORK/$name.o"

# Where nurlc runs from decides how a program's `$` imports resolve. A
# package writes them relative to its own root ("deps/x/src/y.nu"), a
# program in this repo writes them relative to the repo. So: the
# nearest directory at or above the source that has a nurl.toml, else
# the repo root. Guessing wrong is not a subtle failure — nurlc says
# "cannot open deps/…" and stops.
srcdir="$(dirname "$SRC")"
workdir="$ROOT"
probe="$srcdir"
while [ "$probe" != "/" ]; do
    if [ -f "$probe/nurl.toml" ]; then workdir="$probe"; break; fi
    probe="$(dirname "$probe")"
done
cd "$workdir" || exit 2

# The `simd` prefix expands to an x86-64-v3 clone plus a CPUID
# dispatcher, and nurlc emits no target triple to say otherwise — so on
# an aarch64/riscv64 unikernel every marked function would draw one
# "not a recognized feature for this target" line per feature. Ask the
# CROSS compiler what it targets rather than pattern-matching its name:
# NURL_TARGET_CC is a whole command line, and -dumpmachine is the
# answer from the tool that will actually lower the IR.
NURLC_CPU=""
case "$($CC -dumpmachine 2>/dev/null)" in
    x86_64-* | amd64-*) ;;
    *) NURLC_CPU="--no-cpu-dispatch" ;;
esac

"$ROOT/build/nurlc" $NURLC_CPU "$SRC" > "$OUT_LL" 2>"$WORK/compile.err" || fail 3 "$WORK/compile.err" "nurlc"
$CC -O2 -c "$OUT_LL" -o "$OBJ" 2>"$WORK/cc.err" || fail 4 "$WORK/cc.err" "$CC"

# What does the socket shim define? Its own `@ nurl_*` definitions, read
# from the file that defines them.
shim_syms=$(grep -oE '^@ nurl_[A-Za-z0-9_]+' "$SHIM" | awk '{print $2}' | sort -u)
undef=$($NM -u "$OBJ" 2>/dev/null | awk '{print $NF}' | sort -u)
need=""
if [ -n "$shim_syms" ]; then
    need=$(comm -12 <(printf '%s\n' "$undef") <(printf '%s\n' "$shim_syms"))
fi

# The extra modules this program is compiled together with. Two of them,
# and they are decided in two DIFFERENT ways on purpose:
#
#   sockets — MEASURED. A program that opens a socket has the `nurl_tcp_*`
#             symbols undefined in its own object, so `nm` answers the
#             question and no list in this file can drift.
#   disk    — REQUESTED. The disk's `nurl_disk_*` symbols are referenced
#             from C (`boot/vfs.c`), not from the program, so they are
#             never undefined in the object `nm` reads and the same
#             measurement would answer "no" about every program. The
#             build says so instead: `build_unikernel.sh --disk`, which
#             is also the switch that decides whether the image carries
#             a filesystem at all.
extra=()
if [ -n "$need" ]; then
    extra+=("$SHIM")
    # The interface implementation, chosen by the target rather than by
    # a conditional inside the shim: the guest has a virtio-net device,
    # a Linux -nostdlib process has none, and both spellings of "the
    # network" are the same three functions.
    extra+=("${NURL_NETDEV:-$ROOT/unikernel/net/netdev_none.nu}")
fi
keep=""
if [ -n "${NURL_DISK:-}" ]; then
    extra+=("$ROOT/unikernel/fs/disk.nu")
    extra+=("${NURL_BLKDEV:-$ROOT/unikernel/fs/blkdev_none.nu}")
    # The disk shim's entry points have to survive dead-code elimination,
    # and nothing in the module calls them: `boot/vfs.c` does, and the
    # IR has no way to say so. Without this the whole layer is dropped,
    # the image links (the C side's references are weak), and the guest
    # reports "no filesystem" about a filesystem it is carrying — which
    # is exactly what it did. The names are READ from the shim rather
    # than listed here, for the same reason the socket set is measured.
    disk_syms=$(grep -oE '^@ nurl_disk_[A-Za-z0-9_]+' "$ROOT/unikernel/fs/disk.nu" \
                | awk '{print $2}' | sort -u | paste -sd,)
    [ -n "$disk_syms" ] || { echo "compile_nu.sh: no nurl_disk_* in the disk shim" >&2; exit 5; }
    keep="--keep=$disk_syms"
fi
[ ${#extra[@]} -gt 0 ] || exit 0

# Needed. Recompile through a root that imports the program and them.
root_nu="$WORK/__with_shims.nu"
{
    echo "// generated by unikernel/compile_nu.sh — do not edit"
    [ -n "$need" ] && echo "// $name needs:$(printf ' %s' $need)"
    [ -n "${NURL_DISK:-}" ] && echo "// built with a disk"
    printf '$ `%s`\n' "$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
    for m in "${extra[@]}"; do printf '$ `%s`\n' "$m"; done
} > "$root_nu"

"$ROOT/build/nurlc" $NURLC_CPU $keep "$root_nu" > "$OUT_LL" 2>"$WORK/compile.err" || fail 3 "$WORK/compile.err" "nurlc (with shims)"
$CC -O2 -c "$OUT_LL" -o "$OBJ" 2>"$WORK/cc.err" || fail 4 "$WORK/cc.err" "$CC (with shims)"
exit 0
