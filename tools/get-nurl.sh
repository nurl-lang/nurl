#!/usr/bin/env sh
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  get-nurl.sh — one-line installer for the NURL toolchain.
#
#  Detects your OS/arch, downloads the matching release archive from
#  GitHub Releases, verifies its SHA-256, and unpacks the relocatable
#  toolchain into $NURL_HOME (default ~/.nurl). Then add ~/.nurl/bin to
#  PATH (the installer prints the exact line).
#
#  Usage:
#    curl -fsSL https://nurl-lang.org/install.sh | sh
#    curl -fsSL https://nurl-lang.org/install.sh | sh -s -- --version v0.1.0
#
#  Env:
#    NURL_HOME     install prefix (default ~/.nurl)
#    NURL_VERSION  release tag to install (default: latest)
#
#  POSIX sh — no bashisms; works under dash/ash/busybox.
# ============================================================
set -eu

REPO="nurl-lang/nurl"
PREFIX="${NURL_HOME:-$HOME/.nurl}"
VERSION="${NURL_VERSION:-}"

err() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# ── Args ───────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="${2:-}"; shift 2 ;;
        --version=*) VERSION="${1#--version=}"; shift ;;
        --prefix) PREFIX="${2:-}"; shift 2 ;;
        --prefix=*) PREFIX="${1#--prefix=}"; shift ;;
        -h|--help)
            sed -n '5,22p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) err "unknown argument: $1 (try --help)" ;;
    esac
done

# ── Detect target triple ───────────────────────────────────────────────
os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
    Linux) ;;
    Darwin) err "macOS packages are not published yet; build from source (see README)." ;;
    *) err "unsupported OS '$os'. On Windows use the PowerShell installer (install.ps1)." ;;
esac
case "$arch" in
    x86_64|amd64)  target="linux-x86_64-glibc" ;;
    aarch64|arm64) target="linux-arm64-glibc" ;;
    *) err "unsupported architecture '$arch'." ;;
esac

# ── Downloader ─────────────────────────────────────────────────────────
if have curl; then
    dl() { curl -fsSL "$1" -o "$2"; }
    dl_stdout() { curl -fsSL "$1"; }
elif have wget; then
    dl() { wget -qO "$2" "$1"; }
    dl_stdout() { wget -qO- "$1"; }
else
    err "need curl or wget on PATH."
fi

# ── Resolve version (latest release tag if unset) ──────────────────────
if [ -z "$VERSION" ]; then
    info "resolving latest release…"
    VERSION="$(dl_stdout "https://api.github.com/repos/$REPO/releases/latest" \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
    [ -n "$VERSION" ] || err "could not determine the latest release tag; pass --version vX.Y.Z."
fi

archive="nurl-${VERSION}-${target}.tar.gz"
# $NURL_INSTALL_BASE overrides the download base (internal mirror / test).
base="${NURL_INSTALL_BASE:-https://github.com/$REPO/releases/download/$VERSION}"

# ── Download + verify ──────────────────────────────────────────────────
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
info "downloading $archive ($VERSION)…"
dl "$base/$archive" "$tmp/$archive" || err "download failed: $base/$archive"

if dl "$base/$archive.sha256" "$tmp/$archive.sha256" 2>/dev/null; then
    info "verifying checksum…"
    want="$(awk '{print $1}' "$tmp/$archive.sha256")"
    if have sha256sum; then
        got="$(sha256sum "$tmp/$archive" | awk '{print $1}')"
    elif have shasum; then
        got="$(shasum -a 256 "$tmp/$archive" | awk '{print $1}')"
    else
        got=""; info "warning: no sha256sum/shasum — skipping checksum verification."
    fi
    [ -z "$got" ] || [ "$got" = "$want" ] || err "checksum mismatch (expected $want, got $got)."
else
    info "warning: no checksum file published — skipping verification."
fi

# ── Unpack (the archive has a top-level nurl/ dir) ─────────────────────
info "installing to $PREFIX…"
rm -rf "$PREFIX"
mkdir -p "$PREFIX"
tar xzf "$tmp/$archive" -C "$PREFIX" --strip-components=1

[ -x "$PREFIX/bin/nurl" ] || err "install looks incomplete: $PREFIX/bin/nurl missing."

# ── Smoke-test: the shipped binaries must at least *load* ───────────────
# The toolchain binaries are built to depend on libc only, so this should
# always pass. But if a future build regresses and ships a binary with a
# stray shared-library dependency (the original failure was a stray
# libpq.so.5 NEEDED entry that stopped `nurlpkg install` dead on a box with
# no Postgres client), catch it HERE with an actionable message instead of
# letting the user hit a cryptic dynamic-loader error at first use.
smoke() {
    bin="$1"
    [ -x "$bin" ] || return 0
    # Any argument works — the dynamic loader resolves all NEEDED libraries
    # before main() runs, so a missing .so surfaces regardless of CLI args.
    out="$("$bin" --version 2>&1 || true)"
    case "$out" in
        *"error while loading shared libraries"* | *"cannot open shared object"*)
            lib="$(printf '%s\n' "$out" | sed -n 's/.*\(lib[A-Za-z0-9._+-]*\.so[.0-9]*\).*/\1/p' | head -n1)"
            info ""
            info "ERROR: $(basename "$bin") cannot start — missing shared library: ${lib:-(see below)}"
            info "$out"
            info ""
            info "Install the missing library with your package manager, then re-run this installer:"
            info "    Debian/Ubuntu:  sudo apt-get install -y <package that provides ${lib:-the library}>"
            info "    Fedora/RHEL:    sudo dnf install -y     <package that provides ${lib:-the library}>"
            info "    Alpine:         sudo apk add            <package that provides ${lib:-the library}>"
            info ""
            info "Please also report this at https://github.com/nurl-lang/nurl-lang/issues —"
            info "the shipped toolchain is meant to need only libc."
            exit 1
            ;;
    esac
}
smoke "$PREFIX/build/nurlc"
smoke "$PREFIX/build/nurlpkg"

# ── Done ───────────────────────────────────────────────────────────────
info ""
info "NURL $VERSION installed → $PREFIX"
info ""
info "Add it to your shell (and your ~/.bashrc / ~/.zshrc):"
info "    source $PREFIX/env"
info ""
info "Or just add the bin dir to PATH:"
info "    export PATH=\"$PREFIX/bin:\$PATH\""
info ""
info "Then:  nurlc --version   ·   nurlpkg install argz-demo"

# Building a program (and therefore `nurlpkg install <tool>`, which compiles
# the package from source) needs an LLVM compiler. The archive bundles a
# self-contained `zig` for exactly this, so normally nothing is required.
# Only if that bundle is somehow absent does the toolchain fall back to a
# system clang — warn about it then, as a heads-up, not a failure.
if [ ! -x "$PREFIX/zig/zig" ] && ! command -v clang >/dev/null 2>&1; then
    info ""
    info "Heads-up: this archive has no bundled zig backend, so to build"
    info "programs or 'nurlpkg install' a tool you need clang (an LLVM C"
    info "compiler) on PATH. Install it with, e.g.:"
    info "    Debian/Ubuntu:  sudo apt-get install -y clang"
    info "    Fedora/RHEL:    sudo dnf install -y clang"
    info "    Alpine:         sudo apk add clang"
    info "    Arch:           sudo pacman -S clang"
fi
