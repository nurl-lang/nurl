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
#    NURL_HOME              install prefix (default ~/.nurl)
#    NURL_VERSION           release tag to install (default: latest)
#    NURL_NO_MODIFY_PATH    set to 1 to never touch shell rc files / prompt
#    NURL_INSTALL_INSECURE  set to 1 (or pass --insecure) to install even when
#                           the download can't be checksum-verified. OFF by
#                           default: a missing checksum file or a missing
#                           sha256 tool ABORTS the install rather than
#                           silently trusting unverified bytes.
#
#  POSIX sh — no bashisms; works under dash/ash/busybox.
# ============================================================
set -eu

REPO="nurl-lang/nurl"
PREFIX="${NURL_HOME:-$HOME/.nurl}"
VERSION="${NURL_VERSION:-}"
INSECURE="${NURL_INSTALL_INSECURE:-0}"

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
        --insecure) INSECURE=1; shift ;;
        -h|--help)
            sed -n '5,22p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) err "unknown argument: $1 (try --help)" ;;
    esac
done

# ── Detect target triple ───────────────────────────────────────────────
os="$(uname -s)"
arch="$(uname -m)"
case "$arch" in
    x86_64|amd64)  cpu="x86_64" ;;
    aarch64|arm64) cpu="arm64" ;;
    *) cpu="" ;;
esac
case "$os" in
    Linux)
        case "$cpu" in
            x86_64) target="linux-x86_64-glibc" ;;
            arm64)  target="linux-arm64-glibc" ;;
            *) err "unsupported Linux architecture '$arch'." ;;
        esac ;;
    FreeBSD)
        case "$cpu" in
            x86_64) target="freebsd-x86_64" ;;
            *) err "FreeBSD packages are published for x86_64 only (got '$arch'); build from source (see README)." ;;
        esac ;;
    Darwin) err "macOS packages are not published yet; build from source (see README)." ;;
    *) err "unsupported OS '$os'. On Windows use the PowerShell installer (install.ps1)." ;;
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

# Verification is fail-CLOSED: anything that stops us confirming the bytes
# match the published SHA-256 aborts, unless the user set --insecure /
# NURL_INSTALL_INSECURE=1. (Note: the checksum comes from the same release, so
# it defends against a corrupted/truncated download — not against a compromised
# release. Detached signatures would close that; tracked separately.)
insecure_or_die() {
    if [ "$INSECURE" = 1 ]; then
        info "warning: $1 — continuing anyway (--insecure)."
    else
        err "$1. Refusing to install unverified bytes; re-run with --insecure to override."
    fi
}
if dl "$base/$archive.sha256" "$tmp/$archive.sha256" 2>/dev/null; then
    info "verifying checksum…"
    want="$(awk '{print $1}' "$tmp/$archive.sha256")"
    [ -n "$want" ] || insecure_or_die "the published checksum file is empty or malformed"
    if have sha256sum; then
        got="$(sha256sum "$tmp/$archive" | awk '{print $1}')"
    elif have shasum; then
        got="$(shasum -a 256 "$tmp/$archive" | awk '{print $1}')"
    else
        got=""
        insecure_or_die "no sha256sum/shasum on PATH to verify the download"
    fi
    if [ -n "$got" ] && [ -n "$want" ] && [ "$got" != "$want" ]; then
        err "checksum mismatch (expected $want, got $got) — refusing to install."
    fi
else
    insecure_or_die "no checksum file published for $VERSION ($archive.sha256)"
fi

# ── Signature (defense-in-depth beyond the same-release checksum) ──────
# The pinned release public key. A minisign signature proves the archive was
# produced by the holder of the release key, which a same-release checksum
# can't. If minisign is available we verify fail-closed; if it isn't, we do
# NOT force an install of it — the checksum + HTTPS remain the root of trust,
# exactly as with rustup/deno. (nurl's own pure-NURL verifier — stdlib
# minisign.nu — covers the package layer, where nurl is already present.)
MINISIGN_PUB="RWQT5WWtjTnEyaYAG5X4HKCRtb7rFT5psjJVGB5Q9kVQBI71F5jfPWUf"
if have minisign; then
    if dl "$base/$archive.minisig" "$tmp/$archive.minisig" 2>/dev/null; then
        info "verifying signature…"
        minisign -Vm "$tmp/$archive" -P "$MINISIGN_PUB" >/dev/null 2>&1 \
            || err "signature verification FAILED — refusing to install."
        info "signature OK"
    else
        insecure_or_die "no signature (.minisig) published for $VERSION, and minisign is available to check it"
    fi
else
    info "note: minisign not installed — skipping signature check (checksum + HTTPS enforced)."
fi

# ── Unpack (the archive has a top-level nurl/ dir) ─────────────────────
# Guard the destructive wipe: never delete $HOME, /, or a directory that
# isn't ours. Only clear an empty dir or a prior NURL install (has bin/nurl).
case "$PREFIX" in
    ""|/|"$HOME"|"$HOME"/) err "refusing to install into '$PREFIX' — set NURL_HOME to a dedicated directory (e.g. ~/.nurl)." ;;
esac
# An upgrade must not destroy USER state living in the same prefix:
#   credentials          the registry publish token (nurlpkg login)
#   models/              the model cache (hub / nurllama — tens of GB)
#   share/               assets of tools installed via nurlpkg
#   bin/<other tools>    programs installed via nurlpkg install
# Wiping the whole prefix (as this did) silently logged the user out and
# removed every installed tool. Remove only the toolchain's OWN paths —
# the four shipped binaries, build/, stdlib/, docs/, zig/, libexec/, the shims —
# and let tar overwrite the rest. Those directories are removed wholesale
# so a file deleted upstream cannot linger.
#
# Unlinking a RUNNING binary is fine on POSIX (the kernel keeps the inode
# alive for the running process), which is what makes `nurl upgrade` —
# nurlpkg upgrading the very tree it is executing from — safe here. The
# Windows installer has to work around the same case differently.
if [ -e "$PREFIX" ]; then
    if [ -x "$PREFIX/bin/nurl" ] || [ -x "$PREFIX/bin/nurlc" ] || [ -z "$(ls -A "$PREFIX" 2>/dev/null)" ]; then
        rm -rf "$PREFIX/build" "$PREFIX/stdlib" "$PREFIX/docs" "$PREFIX/zig" "$PREFIX/libexec"
        rm -f  "$PREFIX/nurl.sh" "$PREFIX/nurl.bat" "$PREFIX/env" \
               "$PREFIX/bin/nurl" "$PREFIX/bin/nurlc" \
               "$PREFIX/bin/nurlfmt" "$PREFIX/bin/nurlpkg"
    else
        err "'$PREFIX' exists, is not empty, and is not a NURL install (no bin/nurl) — refusing to overwrite it. Remove it yourself or set NURL_HOME to a fresh path."
    fi
fi
info "installing to $PREFIX…"
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
    # glibc ld.so: "error while loading shared libraries: libX.so.N: cannot open…"
    # FreeBSD rtld:  Shared object "libX.so.N" not found, required by "nurlc"
    case "$out" in
        *"error while loading shared libraries"* | *"cannot open shared object"* | *"Shared object"*"not found"*)
            lib="$(printf '%s\n' "$out" | sed -n 's/.*\(lib[A-Za-z0-9._+-]*\.so[.0-9]*\).*/\1/p' | head -n1)"
            info ""
            info "ERROR: $(basename "$bin") cannot start — missing shared library: ${lib:-(see below)}"
            info "$out"
            info ""
            info "Install the missing library with your package manager, then re-run this installer:"
            info "    Debian/Ubuntu:  sudo apt-get install -y <package that provides ${lib:-the library}>"
            info "    Fedora/RHEL:    sudo dnf install -y     <package that provides ${lib:-the library}>"
            info "    Alpine:         sudo apk add            <package that provides ${lib:-the library}>"
            info "    FreeBSD:        sudo pkg install -y     <package that provides ${lib:-the library}>"
            info ""
            info "Please also report this at https://github.com/nurl-lang/nurl/issues —"
            info "the shipped toolchain is meant to need only libc."
            exit 1
            ;;
    esac
}
smoke "$PREFIX/build/nurlc"
smoke "$PREFIX/build/nurlpkg"

# ── PATH setup ─────────────────────────────────────────────────────────
info ""
info "NURL $VERSION installed → $PREFIX"
info ""

BIN_DIR="$PREFIX/bin"
EXPORT_LINE="export PATH=\"$BIN_DIR:\$PATH\""

# The shell rc to persist into, chosen from the user's login shell.
rc_file() {
    case "$(basename "${SHELL:-sh}")" in
        zsh)  printf '%s' "${ZDOTDIR:-$HOME}/.zshrc" ;;
        bash) printf '%s' "$HOME/.bashrc" ;;
        *)    printf '%s' "$HOME/.profile" ;;
    esac
}

case ":${PATH}:" in
    *":$BIN_DIR:"*)
        # Already visible in this shell (e.g. a re-install) — nothing to do.
        info "$BIN_DIR is already on your PATH — you're all set."
        ;;
    *)
        RC="$(rc_file)"
        DO_PERSIST=0
        # Piped installs have the script on stdin, so ask on the terminal
        # directly. No tty (CI, no controlling terminal) ⇒ don't prompt and
        # never modify rc files silently.
        if [ "${NURL_NO_MODIFY_PATH:-0}" = "1" ]; then
            :
        elif ( : > /dev/tty ) 2>/dev/null && ( : < /dev/tty ) 2>/dev/null; then
            # /dev/tty actually opens (a controlling terminal is attached) —
            # an access() check alone passes even with no tty and then aborts.
            # Probe in subshells: a redirection error on the special builtin
            # ':' would otherwise exit the whole (non-interactive) shell.
            printf 'Add %s to your PATH permanently in %s? [Y/n] ' "$BIN_DIR" "$RC" > /dev/tty
            read ANS < /dev/tty || ANS=""
            case "$ANS" in ""|[Yy]*) DO_PERSIST=1 ;; esac
        fi

        if [ "$DO_PERSIST" -eq 1 ]; then
            if [ -e "$RC" ] && grep -qF "$BIN_DIR" "$RC" 2>/dev/null; then
                info "PATH already configured in $RC — left it unchanged."
            elif printf '\n# Added by the NURL installer (https://nurl-lang.org)\n%s\n' "$EXPORT_LINE" >> "$RC" 2>/dev/null; then
                info "Added $BIN_DIR to PATH in $RC — new shells will pick it up."
            else
                info "Could not write to $RC; add this line to your shell rc yourself:"
                info "    $EXPORT_LINE"
            fi
            # A piped `curl | sh` runs in a child shell and cannot change the
            # PATH of the shell you launched it from, so this one still needs
            # the export (or a fresh terminal).
            info ""
            info "This shell won't see it until you run (or open a new terminal):"
            info "    $EXPORT_LINE"
        else
            info "To use NURL in this shell now, run:"
            info "    $EXPORT_LINE"
            info ""
            info "To make it permanent, add that line to your shell rc (e.g. $RC),"
            info "or re-run with a terminal attached to be offered the change."
        fi
        ;;
esac

info ""
info "The shims self-locate the stdlib, so PATH is all you need — no 'source"
info "env' required. (bash/zsh users may instead 'source $PREFIX/env', which"
info "also exports NURL_HOME.)"
info ""
info "Then:  nurl --version   ·   nurlpkg install nq   ·   nurl upgrade  (later)"

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
