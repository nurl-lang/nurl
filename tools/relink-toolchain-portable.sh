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
#  no old clang. nurlc is libc-only and nurlpkg adds only static zlib/zstd
#  (whose symbols are ancient), so a low floor is achievable.
#
#  Usage:  relink-toolchain-portable.sh <x86_64|aarch64> [glibc_version]
#  Env:    NURL_BUNDLE_ZIG  dir containing the `zig` binary (default vendor/zig)
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${1:?usage: relink-toolchain-portable.sh <x86_64|aarch64> [glibc_version]}"
GLIBC_VER="${2:-2.17}"   # 2.17 = manylinux2014 floor; covers ~everything since 2014
TARGET="${ARCH}-linux-gnu.${GLIBC_VER}"

ZIG="${NURL_BUNDLE_ZIG:-$ROOT/vendor/zig}/zig"
[[ -x "$ZIG" ]] || { echo "ERROR: zig not found at $ZIG (set NURL_BUNDLE_ZIG)" >&2; exit 1; }
[[ -f "$ROOT/build/nurlc_self2.ll" ]] || { echo "ERROR: build/nurlc_self2.ll missing — run ./build.sh first" >&2; exit 1; }
[[ -f "$ROOT/build/nurlpkg.ll" ]]     || { echo "ERROR: build/nurlpkg.ll missing — run ./tools/nurlpkg/build.sh first" >&2; exit 1; }
[[ -f "$ROOT/stdlib/runtime.o" ]]     || { echo "ERROR: stdlib/runtime.o missing — run ./build.sh first" >&2; exit 1; }

# nurlc is libc-only — relink straight to the old floor.
echo "Relinking nurlc → $TARGET"
"$ZIG" cc -O2 -flto -target "$TARGET" -Wl,--as-needed \
    "$ROOT/build/nurlc_self2.ll" "$ROOT/stdlib/runtime.o" -lm -lpthread \
    -o "$ROOT/build/nurlc"

# nurlpkg additionally links static zlib + zstd. zig does not search system
# library directories in target mode, so pass the archives by full path;
# they only reference ancient libc symbols, so they don't raise the floor.
ZA=()
for n in libz.a libzstd.a; do
    p="$(find /usr/lib /usr/lib64 /lib -name "$n" 2>/dev/null | head -1)"
    [[ -n "$p" ]] && ZA+=("$p")
done
echo "Relinking nurlpkg → $TARGET (static: ${ZA[*]:-none found})"
"$ZIG" cc -O2 -flto -target "$TARGET" -Wl,--as-needed \
    "$ROOT/build/nurlpkg.ll" "$ROOT/stdlib/runtime.o" -lm -lpthread "${ZA[@]}" \
    -o "$ROOT/build/nurlpkg"

# Report the resulting glibc floor (highest versioned symbol referenced).
echo "Resulting glibc floors:"
for b in nurlc nurlpkg; do
    v="$(objdump -T "$ROOT/build/$b" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
    echo "  $b: ${v:-none (static?)}"
done
echo "Done."
