#!/bin/sh
# tools/install-llvm.sh — the clang/LLVM this repository builds with.
#
# One place for the version and for ITS bytes: the CI image, the dev
# container, the playground image and the workflows that run on bare
# runners all install LLVM through this script, so a bump is the three
# lines below and nothing else.
#
#   tools/install-llvm.sh [--prefix DIR] [--link DIR] [--dev] [--from DIR]
#
#     --prefix DIR  where LLVM goes (default /opt/llvm)
#     --link DIR    also symlink clang, clang++, ld.lld and the llvm-*
#                   tools into DIR (e.g. /usr/local/bin), so `clang` on
#                   PATH is this one
#     --dev         also clang-format and clang-tidy (the dev container)
#     --from DIR    take the release archive from DIR when it is there
#                   (an offline box, a CI cache, a container build handed
#                   it as a context); held to the same sha256 as a download
#
# Why the release archive and not a distro package: Ubuntu 24.04 ships
# clang 18, and apt.llvm.org serves only a moving snapshot of the
# release branch (23.1.6~++<date>), which a rebuild cannot reproduce.
# LLVM's own release archive is the stable release, and it is pinned
# here by version AND by content (the digests are the ones GitHub
# publishes for the release assets).
#
# The archive has no LLVMgold.so, so a GNU ld cannot run its LTO link.
# It does carry lld, and lld reads LLVM bitcode itself: the prefix gets
# a clang config file that makes lld clang's default linker, so every
# `clang … -flto` link works with no flag at the call site.
#
# Like any clang, it links against the system's C runtime: the libc
# headers and crt files (libc6-dev) and GCC's support objects and
# libgcc_s (libgcc-N-dev — crtbeginS.o lives there). A distro `clang`
# package pulls those in as dependencies; with this archive the image or
# runner must have them (GitHub's Ubuntu runners do; the Dockerfiles
# install them).
set -eu

LLVM_VERSION=23.1.5
LLVM_SHA256_X64=c3107384835f788768f614db610e87fba7077f125ca950eb02a78bab0a308065
LLVM_SHA256_ARM64=830ceb70edf63849ce66e97bf85310a3bf2bdd04c860a9f2fa4ef1560e290cef
# The same two archives by GitHub's asset id (immutable), for the second
# route below.
LLVM_ASSET_X64=705660944
LLVM_ASSET_ARM64=705827461

PREFIX=/opt/llvm
LINK_DIR=""
DEV=0
FROM_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --link)   LINK_DIR="$2"; shift 2 ;;
        --dev)    DEV=1; shift ;;
        --from)   FROM_DIR="$2"; shift 2 ;;
        --version) echo "$LLVM_VERSION"; exit 0 ;;
        *) echo "usage: $0 [--prefix DIR] [--link DIR] [--dev] [--from DIR] | --version" >&2; exit 2 ;;
    esac
done

case "$(uname -m)" in
    x86_64|amd64)  ARCH=X64;   SHA="$LLVM_SHA256_X64";   ASSET="$LLVM_ASSET_X64" ;;
    aarch64|arm64) ARCH=ARM64; SHA="$LLVM_SHA256_ARM64"; ASSET="$LLVM_ASSET_ARM64" ;;
    *) echo "install-llvm.sh: no LLVM $LLVM_VERSION archive for $(uname -m)" >&2; exit 1 ;;
esac
command -v zstd >/dev/null 2>&1 || { echo "install-llvm.sh: needs zstd" >&2; exit 1; }

NAME="LLVM-${LLVM_VERSION}-Linux-${ARCH}"
URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/${NAME}.tar.zst"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "$FROM_DIR" ] && [ -f "$FROM_DIR/$NAME.tar.zst" ]; then
    echo "install-llvm.sh: $FROM_DIR/$NAME.tar.zst"
    cp "$FROM_DIR/$NAME.tar.zst" "$TMP/llvm.tar.zst"
else
    echo "install-llvm.sh: $URL"
    # Two routes to the same bytes. github.com/…/releases/download is the
    # usual one, and it has answered 504 for this ~1.2 GB asset for an
    # hour at a time while the REST API's asset endpoint served it; the
    # sha256 check below holds either way, so which route delivered is
    # immaterial.
    if ! curl -fsSL --retry 4 --retry-delay 5 --retry-all-errors -o "$TMP/llvm.tar.zst" "$URL"; then
        API="https://api.github.com/repos/llvm/llvm-project/releases/assets/$ASSET"
        echo "install-llvm.sh: falling back to $API"
        curl -fsSL --retry 8 --retry-delay 5 --retry-all-errors \
            -H "Accept: application/octet-stream" -o "$TMP/llvm.tar.zst" "$API"
    fi
fi
echo "$SHA  $TMP/llvm.tar.zst" | sha256sum -c -

# What the repository runs, and nothing else: the archive unpacks to
# ~12 GB (flang, mlir, lldb, …); this is ~1.8 GB. `lib/clang` is the
# resource directory (builtin headers, compiler-rt with the sanitizer
# runtimes). clang++ / ld.lld / llvm-ranlib / llvm-strip are symlinks in
# the archive and come with their targets.
TOOLS="clang clang++ clang-cpp clang-${LLVM_VERSION%%.*} lld ld.lld lld-link
       llvm-ar llvm-ranlib llvm-nm llvm-objcopy llvm-strip llvm-objdump
       llvm-symbolizer llvm-profdata llvm-cov llvm-as llvm-dis
       llvm-dwarfdump llvm-readelf llvm-size llc opt"
[ "$DEV" = 1 ] && TOOLS="$TOOLS clang-format clang-tidy"
set --
for t in $TOOLS; do set -- "$@" "$NAME/bin/$t"; done
set -- "$@" "$NAME/lib/clang"

mkdir -p "$PREFIX"
zstd -dc --long=31 "$TMP/llvm.tar.zst" | tar -x -C "$PREFIX" --strip-components=1 "$@"

# lld as the default linker (see the header), for C and C++ alike.
for drv in clang clang++; do
    printf '%s\n' '-fuse-ld=lld' > "$PREFIX/bin/$drv.cfg"
done

v="$("$PREFIX/bin/clang" --version | head -1)"
case "$v" in
    *"clang version $LLVM_VERSION"*) echo "install-llvm.sh: $v → $PREFIX" ;;
    *) echo "install-llvm.sh: $PREFIX/bin/clang says '$v', expected $LLVM_VERSION" >&2; exit 1 ;;
esac

if [ -n "$LINK_DIR" ]; then
    mkdir -p "$LINK_DIR"
    for t in $TOOLS; do
        [ -e "$PREFIX/bin/$t" ] && ln -sf "$PREFIX/bin/$t" "$LINK_DIR/$t"
    done
fi
