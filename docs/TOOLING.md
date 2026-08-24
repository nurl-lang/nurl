# Tooling

Host tools alongside the compiler: a formatter (`nurlfmt`, built by
`build.sh`), a language server (`nurl-lsp`), a package manager
(`nurlpkg`), an API-doc generator (`nurldoc`) and a REPL (`tools/repl`)
— each of the latter four builds with its own `tools/<name>/build.sh`.
An editor extension wires the LSP into VS Code / Cursor / Windsurf. On
top of those, registry packages extend the toolchain itself:
`nurl-mcp` (LLM agents drive the local compiler over MCP) and the wasm pair
`wasmbuilder` / `nwasm` (compile NURL to wasm32-wasi and run it, fully
locally).

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
manager covering the full dependency lifecycle: path dependencies, registry
dependencies resolved from [reg.nurl-lang.org](https://reg.nurl-lang.org),
and hybrid path+registry declarations that work both in a repo checkout and
from a published tarball. Manifests use a TOML subset compatible with the
`stdlib/ext/toml.nu` parser.

```bash
mkdir demo-app && cd demo-app
build/nurlpkg init demo-app                  # write nurl.toml skeleton
build/nurlpkg add http-router --path ../router --version 0.2.0
build/nurlpkg install                        # symlink deps/, write nurl.lock
build/nurlpkg verify                         # CI gate: exit 1 on lockfile drift

nurlpkg install nq                           # cargo-install-shaped: fetch a
                                             # registry package, build it, put
                                             # the binary on $NURL_HOME/bin
nurlpkg publish                              # pack + upload (token via
                                             # `nurlpkg login`)
```

Subcommands: `init`, `info` (manifest or registry package), `deps`,
`add`, `remove`, `update` (move dependency requirements to the newest
versions — confirms each on stdin, `--all` takes everything; registry
deps follow the newest published version, path deps the local copy's
`nurl.toml`), `install` (project deps, or a registry program/library),
`lock`, `verify`, `publish`, `login`, `logout [--revoke]`, `search`,
`yank` / `unyank`, `test`, `bench`, `self-update`, `version`, `help`.

**`publish` runs five gates before it packs anything**, and refuses on
any of them — a published version can be yanked but never replaced, so
the tool is deliberately harder to talk into an upload than out of one:
the manifest parses and carries a name + version; every `deps/…` import
is declared in `[dependencies]`; path-deps carry a version requirement
and match the local copies you built against; and — the one that costs
real time — **`src/main.nu` typechecks against the INSTALLED toolchain**,
not the checkout you developed in. That last gate compiles with
`$NURL_STDLIB`'s (or `~/.nurl`'s) compiler and stdlib, front-end only,
because a package can import stdlib files that have shipped for years
while calling a function added to one of them last week: every path
exists, and the tarball still fails to build for everyone who installs
it. If no installed compiler is found the gate WARNs and lets the
publish through rather than passing silently — an unverifiable check
should say so. `--dry-run` runs all five and uploads nothing (and needs
no token).

`self-update` is the odd one out: it upgrades the **toolchain**, not a
package, and `nurl upgrade` is its canonical spelling (that is what the
"a newer NURL toolchain is available" notice prints). It runs the installer
bundled at `$NURL_HOME/libexec/get-nurl.sh`, so the checksum/signature
gates and the "replace the toolchain's files, keep the rest of the prefix"
rule have exactly one implementation. Take care not to read it as a synonym
for `nurlpkg update`, which moves a project's dependency requirements.

## MCP server (`nurl-mcp`)

`nurlpkg install nurl-mcp` — a local MCP server so an LLM agent can drive
the installed toolchain: build, run, type-check, format, compile to
wasm32-wasi (`nurl_build_wasm`), and read the installed stdlib. Stdio by
default (`claude mcp add nurl -- nurl-mcp`); `--http` adds a
token-authenticated network transport with code execution gated behind
`--allow-run`, and `--read-only` strips everything but the analysis tools.

## WebAssembly (`wasmbuilder` + `nwasm`)

The wasm toolchain is two registry packages away — no wasi-sdk, no build
service:

```bash
nurlpkg install wasmbuilder     # NURL → wasm32-wasi, fully local
nurlpkg install nwasm           # pure-NURL wasm runtime

wasmbuilder program.nu          # → program.wasm
nwasm run program.wasm
```

`wasmbuilder` drives nurlc, retargets the emitted IR for wasm32-wasi, and
links with the toolchain's bundled `zig cc` (wasi-libc + wasm-ld built in);
`wasmbuilder --doctor` shows how everything resolves on your machine.
`nwasm` runs wasm32-wasi modules (preopened dirs, `--allow-net` for
sockets, `--allow-gpu` for the CUDA host bridge) on a register-record
interpreter with a **template JIT** on top — on by default,
`NURL_NWASM_JIT=0` keeps the pure interpreter, and metered (`--fuel`),
shared-memory and non-x86-64 runs fall back to it on their own. Its CLI
is a drop-in for the reference `wasmtime`'s `run` subset. Both packages'
READMEs carry the full option surface.
