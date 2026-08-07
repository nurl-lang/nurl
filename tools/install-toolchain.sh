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
#    $PREFIX/docs/                  the documentation tree (nurl-mcp nurl_docs)
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
    rm -rf "$PREFIX/bin" "$PREFIX/build" "$PREFIX/stdlib" "$PREFIX/docs" "$PREFIX/zig" "$PREFIX/nurl.sh" "$PREFIX/env"
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

# Formatter. build.sh builds nurlfmt best-effort, so install it when present
# (a box where it didn't build still gets the rest of the toolchain). Without
# it, `nurlfmt` and the nurl-mcp `nurl_fmt` tool are unavailable.
HAVE_NURLFMT=0
if [[ -x "$ROOT/build/nurlfmt" ]]; then
    install -m755 "$ROOT/build/nurlfmt" "$PREFIX/build/nurlfmt"
    HAVE_NURLFMT=1
else
    echo "Note: build/nurlfmt absent — skipping (run ./build.sh to build it; nurl_fmt tooling will be unavailable)."
fi

# Stdlib tree — including runtime.o, the runtime.<feature> link sentinels
# nurl.sh consults, and any canvas.o. Copy the whole directory so the
# installed driver links exactly like the in-tree one.
cp -a "$ROOT/stdlib/." "$PREFIX/stdlib/"

# Documentation tree — MEMORY.md, CRYPTO.md, spec.md, … This is what the
# nurl-mcp `nurl_docs` tool serves ($NURL_STDLIB/docs, i.e. right here),
# so an agent driving the installed toolchain can read how ownership,
# crypto or async actually behave instead of inferring it from
# signatures. Text only; a few hundred KB.
mkdir -p "$PREFIX/docs"
cp -a "$ROOT/docs/." "$PREFIX/docs/"

# Build driver (resolves build/nurlc + stdlib/runtime.o relative to itself).
install -m755 "$ROOT/nurl.sh" "$PREFIX/nurl.sh"

# ── Bundled installer — this is what `nurl upgrade` runs ───────────────
# Shipping it means an in-place upgrade executes the script that came WITH
# the toolchain you already trust, instead of downloading a script and
# piping it to a shell. It is also the single implementation of "verify the
# archive, then replace the toolchain's own paths and keep everything else
# in the prefix" — nothing reimplements that in NURL.
mkdir -p "$PREFIX/libexec"
if [[ -f "$ROOT/tools/get-nurl.sh" ]]; then
    install -m755 "$ROOT/tools/get-nurl.sh" "$PREFIX/libexec/get-nurl.sh"
else
    echo "Note: tools/get-nurl.sh absent — 'nurl upgrade' will not be available."
fi

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

if [[ "$HAVE_NURLFMT" == "1" ]]; then
    cat > "$PREFIX/bin/nurlfmt" <<'EOF'
#!/bin/sh
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export NURL_STDLIB="${NURL_STDLIB:-$HERE}"
exec "$HERE/build/nurlfmt" "$@"
EOF
    chmod +x "$PREFIX/bin/nurlfmt"
fi

# ── Sourceable env (bash / zsh / POSIX sh) ─────────────────────────────
# bash and zsh can self-locate the sourced file (so a moved/extracted tree
# still resolves) — but POSIX sh (dash/ash, FreeBSD /bin/sh) has no portable
# way to find a sourced file's path, and the old `${BASH_SOURCE[0]}` form is a
# bash-array reference that makes those shells abort with "Bad substitution".
# So: bash/zsh resolve dynamically; every other shell falls back to the path
# baked in at install time. The relocatable PATH shims (nurl/nurlc/…) self-
# locate regardless, so a moved tree still works from the shims even when this
# fallback is stale. Baked line written unquoted; the rest is a quoted heredoc.
{
    printf '# NURL toolchain environment — source from your shell rc (bash/zsh/sh).\n'
    printf '__nurl_default=%s\n' "$PREFIX"
    cat <<'EOF'
if [ -n "${BASH_SOURCE:-}" ]; then
    __nurl_here="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"
elif [ -n "${ZSH_VERSION:-}" ]; then
    __nurl_here="$(cd "$(dirname "$0")" && pwd)"
else
    __nurl_here="$__nurl_default"
fi
export NURL_HOME="$__nurl_here"
export NURL_STDLIB="$__nurl_here"
case ":$PATH:" in
    *":$__nurl_here/bin:"*) ;;
    *) export PATH="$__nurl_here/bin:$PATH" ;;
esac
unset __nurl_here __nurl_default
EOF
} > "$PREFIX/env"

echo "Done."
echo
if [[ "$HAVE_NURLFMT" == "1" ]]; then
    echo "  installed:  nurl, nurlc, nurlpkg, nurlfmt  → $PREFIX/bin"
else
    echo "  installed:  nurl, nurlc, nurlpkg  → $PREFIX/bin"
fi
echo "  stdlib:     \$NURL_STDLIB                  → $PREFIX/stdlib"
echo "  docs:                                     → $PREFIX/docs"
echo
echo "Activate it in this shell and future ones:"
echo "    source $PREFIX/env"
echo "    # and add that line to your ~/.bashrc / ~/.zshrc"
echo
echo "Then, from anywhere:"
echo "    nurlpkg install nq             # fetch + build + install a registry program"
echo "    nurl --version                 # what you have"
echo "    nurl upgrade                   # move to the newest release, in place"
