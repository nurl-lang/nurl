#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  install.sh — single-command install of NURL's developer
#                experience.
#
#  Stages (each skippable; idempotent on re-run):
#    1. Bootstrap the compiler  (zig build bootstrap if build/nurlc missing)
#    2. Build the LSP server    (zig build nurl-lsp)
#    3. Symlink build/nurl-lsp into ~/.local/bin/nurl-lsp so VS Code
#       and Windsurf find it on $PATH without any setting tweaks.
#    4. Package + install the VS Code extension via the `code` CLI
#       (or `windsurf` / `cursor`). Skipped when none is on $PATH.
#
#  Flags:
#    --no-vscode   Don't try to install the VS Code extension even
#                  if `code` is on PATH.
#    --no-path     Don't touch ~/.local/bin — leave the binary where
#                  build.sh put it (build/nurl-lsp).
#    --force       Rebuild even if the artefacts already exist.
#    --uninstall   Remove ~/.local/bin/nurl-lsp + the installed
#                  extension; leave the build tree alone.
#    -h | --help   Show this help.
#
#  Stderr/stdout: clearly-labelled stage banners; failures print the
#  underlying tool's output and exit 1.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NO_VSCODE=0
NO_PATH=0
FORCE=0
UNINSTALL=0

usage() { sed -n '4,29p' "$0" | sed 's/^# \?//'; exit 0; }

for arg in "$@"; do
    case "$arg" in
        --no-vscode)  NO_VSCODE=1 ;;
        --no-path)    NO_PATH=1 ;;
        --force)      FORCE=1 ;;
        --uninstall)  UNINSTALL=1 ;;
        -h|--help)    usage ;;
        *) echo "unknown arg: $arg (try --help)" >&2; exit 2 ;;
    esac
done

# ── helpers ───────────────────────────────────────────────────
banner() { printf '\n\033[1;36m── %s\033[0m\n' "$*"; }
ok()     { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn()   { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()    { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

editor_cli=""
for c in code cursor windsurf; do
    if command -v "$c" >/dev/null 2>&1; then editor_cli="$c"; break; fi
done

# ── uninstall path ───────────────────────────────────────────
if (( UNINSTALL == 1 )); then
    banner "Uninstall"
    bin="$HOME/.local/bin/nurl-lsp"
    if [[ -e "$bin" || -L "$bin" ]]; then
        rm -f "$bin"
        ok "removed $bin"
    else
        warn "$bin not present"
    fi
    if [[ -n "$editor_cli" ]]; then
        if "$editor_cli" --list-extensions 2>/dev/null | grep -q '^nurl-lang\.nurl$'; then
            "$editor_cli" --uninstall-extension nurl-lang.nurl >/dev/null 2>&1 || true
            ok "uninstalled VS Code extension nurl-lang.nurl"
        else
            warn "VS Code extension nurl-lang.nurl not installed"
        fi
    fi
    echo
    ok "Uninstall complete. The build/ tree is untouched."
    exit 0
fi

# ── 1. Bootstrap compiler ────────────────────────────────────
banner "1/4 Compiler bootstrap"
if (( FORCE == 1 )) || [[ ! -x build/nurlc ]]; then
    echo "  zig build bootstrap (this can take a minute)..."
    if ! zig build bootstrap >/tmp/nurl_install_build.log 2>&1; then
        tail -30 /tmp/nurl_install_build.log
        die "zig build bootstrap failed (full log: /tmp/nurl_install_build.log)"
    fi
    ok "build/nurlc ready"
else
    ok "build/nurlc already present (use --force to rebuild)"
fi

# ── 2. Build LSP ─────────────────────────────────────────────
banner "2/4 Language Server"
if (( FORCE == 1 )) || [[ ! -x build/nurl-lsp ]]; then
    if ! zig build nurl-lsp >/tmp/nurl_install_lsp.log 2>&1; then
        tail -30 /tmp/nurl_install_lsp.log
        die "zig build nurl-lsp failed (full log: /tmp/nurl_install_lsp.log)"
    fi
    ok "build/nurl-lsp built"
else
    ok "build/nurl-lsp already present"
fi

# ── 3. Symlink to ~/.local/bin ───────────────────────────────
if (( NO_PATH == 0 )); then
    banner "3/4 PATH install"
    bindir="$HOME/.local/bin"
    mkdir -p "$bindir"
    src="$(realpath build/nurl-lsp)"
    dst="$bindir/nurl-lsp"
    if [[ -e "$dst" || -L "$dst" ]]; then
        cur="$(readlink -f "$dst" 2>/dev/null || echo "")"
        if [[ "$cur" == "$src" ]]; then
            ok "$dst already points at $src"
        else
            ln -sf "$src" "$dst"
            ok "updated $dst → $src (was $cur)"
        fi
    else
        ln -sf "$src" "$dst"
        ok "linked $dst → $src"
    fi
    case ":$PATH:" in
        *":$bindir:"*) ok "$bindir on PATH" ;;
        *) warn "$bindir is NOT on \$PATH — add this to your shell rc:"
           echo "    export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
else
    banner "3/4 PATH install (skipped — --no-path)"
fi

# ── 4. VS Code extension ─────────────────────────────────────
if (( NO_VSCODE == 1 )); then
    banner "4/4 VS Code extension (skipped — --no-vscode)"
elif [[ -z "$editor_cli" ]]; then
    banner "4/4 VS Code extension (skipped — no editor CLI)"
    warn "neither 'code', 'cursor', nor 'windsurf' is on PATH"
    warn "install the .vsix manually: tooling/vscode-nurl/nurl-<ver>.vsix"
else
    banner "4/4 VS Code extension via '$editor_cli'"
    if ! command -v npx >/dev/null 2>&1; then
        warn "npx not on PATH — install Node.js to build the .vsix"
        warn "(syntax highlighting + LSP still work via Manual install)"
    else
        ver="$(grep -oP '"version":\s*"\K[^"]+' tooling/vscode-nurl/package.json)"
        vsix="tooling/vscode-nurl/nurl-${ver}.vsix"
        if (( FORCE == 1 )) || [[ ! -f "$vsix" ]]; then
            echo "  packaging $vsix ..."
            (
                cd tooling/vscode-nurl
                [[ -d node_modules ]] || npm install --silent
                npx --yes vsce package -o "nurl-${ver}.vsix" >/tmp/nurl_install_vsce.log 2>&1 \
                    || { tail -30 /tmp/nurl_install_vsce.log; die "vsce package failed"; }
            )
        fi
        ok "$vsix ready"
        installed="$("$editor_cli" --list-extensions --show-versions 2>/dev/null | grep '^nurl-lang\.nurl@' || true)"
        if [[ "$installed" == "nurl-lang.nurl@${ver}" ]] && (( FORCE == 0 )); then
            ok "$editor_cli already has nurl-lang.nurl@${ver}"
        else
            "$editor_cli" --install-extension "$vsix" --force >/tmp/nurl_install_ext.log 2>&1 \
                || { tail -30 /tmp/nurl_install_ext.log; die "$editor_cli --install-extension failed"; }
            ok "installed nurl-lang.nurl@${ver} into $editor_cli"
        fi
    fi
fi

echo
banner "Done"
echo "  Open a .nu file in your editor; the LSP will start automatically."
echo "  Smoke test: gdb-batch via ./tools/dwarf_test.sh, or just open"
echo "  examples/fizzbuzz.nu and hover over a function name."
echo "  Re-run any time — this script is idempotent."
echo "  Uninstall: ./install.sh --uninstall"
