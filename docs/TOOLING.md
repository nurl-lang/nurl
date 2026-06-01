# Tooling

The build produces three host tools alongside the compiler: a formatter
(`nurlfmt`), a language server (`nurl-lsp`), and a package manager
(`nurlpkg`). An editor extension wires the LSP into VS Code / Cursor /
Windsurf.

## Editor support

Syntax highlighting **plus a full Language Server** (go-to-definition,
hover, document outline, completion, workspace symbol search, folding,
`nurlfmt`-backed formatting, live compile diagnostics) for VS Code, Cursor,
and Windsurf lives in [`tooling/vscode-nurl/`](../tooling/vscode-nurl/).

**One-command install from a checkout:**
```bash
git clone https://github.com/nurl-lang/nurl.git
cd nurl
./install.sh
```

`install.sh` is idempotent — re-run any time. It bootstraps the compiler,
builds `nurl-lsp`, symlinks it into `~/.local/bin/`, packages the VS Code
extension, and installs it via the editor's CLI (`code` / `cursor` /
`windsurf`, whichever is on `PATH`). Flags: `--no-vscode`, `--no-path`,
`--force`, `--uninstall`.

**Manual install:** `./build.sh` then `./tools/nurl-lsp/build.sh`, then in
the editor `Ctrl+Shift+P` → "Extensions: Install from VSIX…" and select the
packaged `.vsix` under `tooling/vscode-nurl/`.

The browser playground ships a Monaco port of the same tokenizer — no
install required (see [`PLAYGROUND.md`](PLAYGROUND.md)).

## Canonical formatter (`nurlfmt`)

`./build.sh` produces `build/nurlfmt` — a deterministic, opinionated source
formatter analogous to `gofmt` / `rustfmt`. The full rule set is specified
in [`FORMAT.md`](FORMAT.md).

```bash
./nurlfmt.sh <file.nu>              # format → stdout
./nurlfmt.sh --write   <file.nu> …  # rewrite in place
./nurlfmt.sh --check   <file.nu> …  # CI gate; exit 1 if non-canonical
cat src.nu | ./nurlfmt.sh           # stdin → stdout
```

Round-trip acceptance — every shipped `.nu` file round-trips
byte-for-byte: `fmt(fmt(x)) == fmt(x)` AND `nurlc(fmt(x)) == nurlc(x)`,
enforced by `compiler/tests/nurlfmt_idempotent.sh`.

## Language Server (`nurl-lsp`)

`./tools/nurl-lsp/build.sh` produces `build/nurl-lsp` — a stdio JSON-RPC
server with diagnostics, go-to-definition, hover, document symbols,
completion, formatting, workspace symbol search, and folding ranges. Wired
to the editors through the `tooling/vscode-nurl` extension.

## Package manager (`nurlpkg`)

`./tools/nurlpkg/build.sh` produces `build/nurlpkg` — a Cargo-shaped package
manager covering the full dependency lifecycle for path-based dependencies
(registry-style version resolution is out of scope for v1). Manifests use a
TOML subset compatible with the `stdlib/ext/toml.nu` parser.

```bash
build/nurlpkg init demo-app                  # write nurl.toml skeleton
cd demo-app
build/nurlpkg add http-router --path ../router --version 0.2.0
build/nurlpkg install                        # symlink deps/, write nurl.lock
build/nurlpkg verify                         # CI gate: exit 1 on lockfile drift
```

Subcommands: `init`, `info`, `deps`, `add`, `remove`, `install`, `lock`,
`verify`, `version`, `help`.
