#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  relink-toolchain-portable.sh — relink the shipped nurlc + nurlpkg
#  against an OLD glibc baseline using the bundled zig.
#
#  The release binaries are built on a modern CI runner (e.g. glibc 2.39),
#  so they reference recent versioned symbols (notably GLIBC_2.34, where
#  pthread folded into libc) and refuse to start on an older distro — e.g.
#  Raspberry Pi OS bullseye (glibc 2.31):
#      libc.so.6: version `GLIBC_2.34' not found (required by .../nurlpkg)
#  glibc is backward- but not forward-compatible, so the fix is to build
#  against a LOW glibc floor. zig ships versioned glibc stubs, so we can
#  build on the modern runner yet target an old floor — no old container,
#  no old clang.
#
#  We deliberately DON'T use `-flto` here: monolithic/thin LTO of nurlc's
#  large module fails on the arm64 release runner (silent exit after the
#  frontend). Instead we recompile runtime.c from source with zig at the
#  old target and link without LTO. To stay lean without LTO's dead-code
#  elimination, nurlpkg's runtime is built with ONLY the zlib/zstd back-ends
#  it actually uses (not curl/openssl/sqlite/pq), and nurlc's with none —
#  so each links against just what it needs. Floor lands ~glibc 2.25
#  (getrandom), which still covers the Pi (2.31) and beyond.
#
#  Usage:  relink-toolchain-portable.sh <x86_64|aarch64> [glibc_version]
#  Env:    NURL_BUNDLE_ZIG  dir containing the `zig` binary (default vendor/zig)
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${1:?usage: relink-toolchain-portable.sh <x86_64|aarch64> [glibc_version]}"
GLIBC_VER="${2:-2.28}"   # >= 2.25 (runtime uses getrandom); 2.28 covers Pi/ODROID with margin
TARGET="${ARCH}-linux-gnu.${GLIBC_VER}"
MULTIARCH="${ARCH}-linux-gnu"

ZIG="${NURL_BUNDLE_ZIG:-$ROOT/vendor/zig}/zig"
[[ -x "$ZIG" ]] || { echo "ERROR: zig not found at $ZIG (set NURL_BUNDLE_ZIG)" >&2; exit 1; }
[[ -f "$ROOT/build/nurlc_self2.ll" ]] || { echo "ERROR: build/nurlc_self2.ll missing — run ./build.sh first" >&2; exit 1; }
[[ -f "$ROOT/build/nurlpkg.ll" ]]     || { echo "ERROR: build/nurlpkg.ll missing — run ./tools/nurlpkg/build.sh first" >&2; exit 1; }
[[ -f "$ROOT/stdlib/runtime.c" ]]     || { echo "ERROR: stdlib/runtime.c missing" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# nurlc is libc-only: recompile runtime.c with no back-end defines, link
# without LTO straight to the old floor.
echo "Relinking nurlc → $TARGET"
"$ZIG" cc -O2 -target "$TARGET" -c "$ROOT/stdlib/runtime.c" -o "$TMP/rt-nurlc.o"
"$ZIG" cc -O2 -target "$TARGET" -Wl,--as-needed \
    "$ROOT/build/nurlc_self2.ll" "$TMP/rt-nurlc.o" -lm -lpthread \
    -o "$ROOT/build/nurlc"

# nurlpkg uses zlib + zstd (gzip/zstd of package tarballs) and nothing else
# native. Build its runtime with ONLY those back-ends so the link stays lean
# (no curl/openssl/sqlite/pq) without needing LTO's DCE. zig ignores system
# libc headers by default; `-idirafter` only supplies the missing zlib.h /
# zstd.h, without overriding zig's own target libc headers. zlib + zstd are
# linked statically (full path — zig doesn't search system lib dirs in target
# mode); their symbols are ancient, so they don't raise the floor.
echo "Relinking nurlpkg → $TARGET"
"$ZIG" cc -O2 -target "$TARGET" -DNURL_HAVE_ZLIB -DNURL_HAVE_ZSTD \
    -idirafter /usr/include -idirafter "/usr/include/$MULTIARCH" \
    -c "$ROOT/stdlib/runtime.c" -o "$TMP/rt-nurlpkg.o"
ZA=()
for n in libz.a libzstd.a; do
    p="$(find /usr/lib /usr/lib64 /lib -name "$n" 2>/dev/null | head -1)"
    [[ -n "$p" ]] && ZA+=("$p")
done
"$ZIG" cc -O2 -target "$TARGET" -Wl,--as-needed \
    "$ROOT/build/nurlpkg.ll" "$TMP/rt-nurlpkg.o" -lm -lpthread "${ZA[@]}" \
    -o "$ROOT/build/nurlpkg"

# Report the resulting glibc floor (highest versioned symbol referenced).
echo "Resulting glibc floors:"
for b in nurlc nurlpkg; do
    v="$(readelf -V "$ROOT/build/$b" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
    echo "  $b: ${v:-none}"
done
echo "Done."
