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
    rm -rf "$PREFIX/bin" "$PREFIX/build" "$PREFIX/stdlib" "$PREFIX/nurl.sh" "$PREFIX/env"
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

# ── PATH shims ─────────────────────────────────────────────────────────
# Each shim defaults $NURL_STDLIB to the prefix so the compiler finds the
# shipped stdlib from any working directory, even if the user never
# sourced env. The nurlpkg shim additionally points $NURL / $NURLPKG at
# the installed driver so `nurlpkg install <name>` builds with them.
cat > "$PREFIX/bin/nurl" <<EOF
#!/usr/bin/env bash
export NURL_STDLIB="\${NURL_STDLIB:-$PREFIX}"
exec "$PREFIX/nurl.sh" "\$@"
EOF

cat > "$PREFIX/bin/nurlc" <<EOF
#!/usr/bin/env bash
export NURL_STDLIB="\${NURL_STDLIB:-$PREFIX}"
exec "$PREFIX/build/nurlc" "\$@"
EOF

cat > "$PREFIX/bin/nurlpkg" <<EOF
#!/usr/bin/env bash
export NURL_STDLIB="\${NURL_STDLIB:-$PREFIX}"
export NURL="\${NURL:-$PREFIX/bin/nurl}"
export NURLPKG="\${NURLPKG:-$PREFIX/bin/nurlpkg}"
exec "$PREFIX/build/nurlpkg" "\$@"
EOF

chmod +x "$PREFIX/bin/nurl" "$PREFIX/bin/nurlc" "$PREFIX/bin/nurlpkg"

# ── Sourceable env ─────────────────────────────────────────────────────
cat > "$PREFIX/env" <<EOF
# NURL toolchain environment — source this from your shell rc.
export NURL_HOME="$PREFIX"
export NURL_STDLIB="$PREFIX"
case ":\$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *) export PATH="$PREFIX/bin:\$PATH" ;;
esac
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
