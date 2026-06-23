#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  install-toolchain.sh — install the NURL compiler + package
#  manager + stdlib into a self-contained prefix, and wire up
#  the paths that make them work from any directory.
#
#  This is what turns NURL from "a thing you build in the
#  monorepo" into an installed toolchain: after running this and
#  sourcing the printed env line, `nurl`, `nurlc`, and `nurlpkg`
#  are on $PATH, $NURL_STDLIB points at the shipped stdlib (so the
#  compiler resolves `$ `stdlib/...`` imports from anywhere), and
#  `nurlpkg install <name>` can fetch, build, and install programs
#  from the registry.
#
#  Layout ($NURL_HOME, default ~/.nurl):
#    $PREFIX/build/nurlc            the compiler
#    $PREFIX/build/nurlpkg          the package manager
#    $PREFIX/stdlib/                the stdlib tree (+ runtime.o, sentinels)
#    $PREFIX/nurl.sh               the .nu → native build driver
#    $PREFIX/bin/{nurl,nurlc,nurlpkg}   PATH shims (export NURL_STDLIB)
#    $PREFIX/env                   sourceable: exports NURL_STDLIB + PATH
#
#  Usage:
#    ./tools/install-toolchain.sh            install to ~/.nurl (or $NURL_HOME)
#    NURL_HOME=/opt/nurl ./tools/install-toolchain.sh
#    ./tools/install-toolchain.sh --uninstall
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${NURL_HOME:-$HOME/.nurl}"

if [[ "${1:-}" == "--uninstall" ]]; then
    rm -rf "$PREFIX/bin" "$PREFIX/build" "$PREFIX/stdlib" "$PREFIX/zig" "$PREFIX/nurl.sh" "$PREFIX/env"
    echo "Removed NURL toolchain from $PREFIX"
    echo "(You may want to drop the 'source $PREFIX/env' line from your shell rc.)"
    exit 0
fi

# ── Preconditions: the build artefacts must already exist ──────────────
[[ -x "$ROOT/build/nurlc" ]]   || { echo "ERROR: build/nurlc missing — run ./build.sh first" >&2; exit 1; }
[[ -x "$ROOT/build/nurlpkg" ]] || { echo "ERROR: build/nurlpkg missing — run ./tools/nurlpkg/build.sh first" >&2; exit 1; }
[[ -f "$ROOT/stdlib/runtime.o" ]] || { echo "ERROR: stdlib/runtime.o missing — run ./build.sh first" >&2; exit 1; }
[[ -f "$ROOT/nurl.sh" ]]       || { echo "ERROR: nurl.sh missing" >&2; exit 1; }

echo "Installing NURL toolchain → $PREFIX"
mkdir -p "$PREFIX/bin" "$PREFIX/build" "$PREFIX/stdlib"

# Compiler + package manager.
install -m755 "$ROOT/build/nurlc"   "$PREFIX/build/nurlc"
install -m755 "$ROOT/build/nurlpkg" "$PREFIX/build/nurlpkg"

# Stdlib tree — including runtime.o, the runtime.<feature> link sentinels
# nurl.sh consults, and any canvas.o. Copy the whole directory so the
# installed driver links exactly like the in-tree one.
cp -a "$ROOT/stdlib/." "$PREFIX/stdlib/"

# Build driver (resolves build/nurlc + stdlib/runtime.o relative to itself).
install -m755 "$ROOT/nurl.sh" "$PREFIX/nurl.sh"

# ── Bundle a self-contained zig backend (optional but recommended) ─────
# `nurl.sh` prefers a bundled `zig cc` over a system clang: zig carries its
# own modern LLVM (parses nurlc's opaque-pointer IR), its own lld linker
# and libc headers, so *building* a program — and therefore
# `nurlpkg install <tool>` — needs no system compiler and is immune to the
# box's LLVM version. Point $NURL_BUNDLE_ZIG at an extracted zig dist (the
# directory containing the `zig` binary and its `lib/`); the release
# workflow downloads the per-arch dist and sets it. Copied to
# $PREFIX/zig/, which is exactly where nurl.sh looks ($SCRIPT_DIR/zig/zig).
ZIG_SRC="${NURL_BUNDLE_ZIG:-$ROOT/vendor/zig}"
if [[ -x "$ZIG_SRC/zig" ]]; then
    echo "Bundling zig backend from $ZIG_SRC"
    rm -rf "$PREFIX/zig"
    mkdir -p "$PREFIX/zig"
    cp -a "$ZIG_SRC/." "$PREFIX/zig/"
    chmod +x "$PREFIX/zig/zig"
else
    echo "Note: no bundled zig ($ZIG_SRC/zig absent) — the installed toolchain"
    echo "      will fall back to a system clang to build programs."
fi

# ── PATH shims (RELOCATABLE) ───────────────────────────────────────────
# Each shim resolves the prefix from its OWN location at runtime, so the
# whole tree can be moved/extracted anywhere (this is what lets the
# release tarball be unpacked to any path). It defaults $NURL_STDLIB to
# the prefix so the compiler finds the shipped stdlib from any working
# directory, even if the user never sourced env. The nurlpkg shim also
# points $NURL / $NURLPKG at the installed driver so `nurlpkg install
# <name>` builds with them. Quoted heredoc → no install-time expansion.
# POSIX sh shims (not bash) — the installed toolchain must work on a stock
# FreeBSD / Alpine / busybox box where /bin/sh is not bash. `$0` is the shim
# path when executed, so the prefix self-locates without ${BASH_SOURCE}.
cat > "$PREFIX/bin/nurl" <<'EOF'
#!/bin/sh
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export NURL_STDLIB="${NURL_STDLIB:-$HERE}"
exec "$HERE/nurl.sh" "$@"
EOF

cat > "$PREFIX/bin/nurlc" <<'EOF'
#!/bin/sh
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export NURL_STDLIB="${NURL_STDLIB:-$HERE}"
exec "$HERE/build/nurlc" "$@"
EOF

cat > "$PREFIX/bin/nurlpkg" <<'EOF'
#!/bin/sh
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export NURL_STDLIB="${NURL_STDLIB:-$HERE}"
export NURL="${NURL:-$HERE/bin/nurl}"
export NURLPKG="${NURLPKG:-$HERE/bin/nurlpkg}"
exec "$HERE/build/nurlpkg" "$@"
EOF

chmod +x "$PREFIX/bin/nurl" "$PREFIX/bin/nurlc" "$PREFIX/bin/nurlpkg"

# ── Sourceable env (RELOCATABLE) ───────────────────────────────────────
# Resolves its own directory when sourced, so a moved/extracted tree still
# points NURL_HOME / NURL_STDLIB / PATH at the right place.
cat > "$PREFIX/env" <<'EOF'
# NURL toolchain environment — source this from your shell rc.
__nurl_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export NURL_HOME="$__nurl_here"
export NURL_STDLIB="$__nurl_here"
case ":$PATH:" in
    *":$__nurl_here/bin:"*) ;;
    *) export PATH="$__nurl_here/bin:$PATH" ;;
esac
unset __nurl_here
EOF

echo "Done."
echo
echo "  installed:  nurl, nurlc, nurlpkg  → $PREFIX/bin"
echo "  stdlib:     \$NURL_STDLIB          → $PREFIX/stdlib"
echo
echo "Activate it in this shell and future ones:"
echo "    source $PREFIX/env"
echo "    # and add that line to your ~/.bashrc / ~/.zshrc"
echo
echo "Then, from anywhere:"
echo "    nurlpkg install argz-demo     # fetch + build + install a registry program"
