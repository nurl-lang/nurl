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

The server finds `nurlc` and `nurlfmt` from initialization options
`compilerPath` / `formatterPath`, then `NURLC` / `NURLFMT`, then beside its
own executable, then on `PATH`. Explicit configuration takes precedence even
if it is invalid: execution failures produce diagnostics or formatting errors.
An installed layout can put all three binaries in `<prefix>/bin` or
`<prefix>/build` and its sources in `<prefix>/stdlib`. The server discovers
that stdlib directory unless `NURL_STDLIB` or `stdlibRoot` selects another.
The current toolchain installer does not bundle the LSP automatically; build
and place the server alongside the compiler or configure its paths explicitly.

Initialization selects the workspace root for project imports. Each diagnostic
compile passes the current document over stdin with its original filename:
`nurlc --lint --stdin --check -- <file.nu>`. This preserves sibling imports,
source locations and unsaved edits without writing source temporary files.
`--check` performs the normal semantic checks but discards buffered LLVM IR;
it does not write stdout IR or split files. The compiler still constructs IR
during its fused frontend walk. `--stdin` also works without `--check` for
ordinary compilation, including a logical filename that does not exist yet.

The server uses UTF-16 positions for diagnostics, cursor lookup and formatting,
percent-encoded file URIs for imported definitions, and related locations for
errors in imported files. Its declaration index remains a lightweight scanner,
not compiler name resolution; duplicate names, invalidation and other editor
features require their own coverage. The synchronous subprocess API also has
no per-request timeout. These limits are not closed by the diagnostics tests.

After building the compiler and server, exercise relocated binaries and a
separate consumer project with `python3 tools/tests/test_lsp_toolchain.py`.
`python3 tools/tests/test_source_io.py` independently tests the C source readers
under ASan/UBSan, including capacity boundaries, pipes and I/O failures.

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

Registry dependencies carry a `(registry URL, package name)` identity through
resolution, index caching, downloads, signature checks and `nurl.lock`.
An explicit dependency `registry` selects that origin; transitive index
requirements inherit their parent's registry. Custom `resolve_registry` fetch
callbacks receive `(registry, name)` and return `!RegIndex RegistryFetchErr`.
A successful index owns its fields; `registry_index_decode` validates raw JSON
and binds it to the requested name. Only `RegistryNotFound` (HTTP 404) permits
missing-package backtracking. Other HTTP statuses, transport failures and
malformed responses abort resolution with their origin and cause; install,
info, update and the publish dependency gate report the failure. Failed
resolution preserves the existing manifest and lock.

URL normalization lowercases the
scheme and host, removes the default port and adds a trailing slash. Path bytes
are preserved. Credentials, queries and fragments are rejected.

For private registries, configure signing keys in
`$NURL_HOME/registries.toml` (or `~/.nurl/registries.toml` when `NURL_HOME` is
unset). `NURL_REGISTRY_CONFIG` selects an explicit file instead:

```toml
[registries]
"https://packages.example.org/" = "<minisign public-key base64 payload>"
"https://another.example.org/team/" = "<that registry's public-key payload>"
```

Obtain each key from the registry operator through a trusted channel. Downloaded
manifests and index responses cannot add trusted keys. The public NURL registry
has a built-in key. An absent default config is allowed; an unreadable explicit
file, malformed key or conflicting keys for one normalized URL fail the install.
The legacy `NURL_REGISTRY_PUBKEY` variable is scoped to `NURL_REGISTRY`, or to
the public default when that variable is absent. It cannot authorize another
explicit dependency registry. A conflicting file/env pin is an error.

Index fields must have the expected JSON types and contain no embedded NUL;
malformed indexes and truncated text sources are rejected before archive downloads.
Every registry archive requires a matching SHA-256 and minisign signature.
Before extraction, its root `nurl.toml` must name the requested package and
version exactly, and all archive paths and member types are checked. Failed
resolution or authentication returns nonzero, preserves the prior lock and
prints no project installation success. `nurlpkg lock` retains existing source
and checksum fields and refuses missing/renamed registry packages or
installed-version drift. Local development versions can still be refreshed.

Resolution selects one version per `(registry, name)` and backtracks when a
candidate's dependencies conflict. It tries non-yanked versions in descending
SemVer order, choosing the package with the fewest remaining candidates first.
Package name and normalized registry URL break package ties; descending lexical
build metadata breaks equal SemVer precedence ties. Input order does not select
the result. This policy finds a compatible selection when one exists in the
finite fetched graph; it does not promise to maximize every package's version.
Cycles are checked against existing assignments, and long chains have no
arbitrary iteration limit. Indexes and distinct requirements are parsed once
per resolution. Invalid versions, dependency requirements and duplicate version
identities make an index invalid, including metadata of unselected versions.

The resolver can distinguish equal package names in separate registries, but
the current `deps/<name>` installation layout cannot expose both. The CLI
reports that conflict before downloading archives. Frozen-lock installation,
typed transport failures and an atomic transaction across the whole dependency
tree remain tracked in `docs/dev/V1_HARDENING.md`.

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
it. A missing target root, missing compiler, failed compiler launch or
compiler diagnostic refuses publication, including `--dry-run`. Install the
target toolchain before retrying. The compiler runs directly with `--check`;
toolchain paths are literal arguments, and no C compiler or linker is needed.
`--dry-run` runs all five and uploads nothing (and needs
no token). Know what that gate does **not** cover: a **library** package
has no `src/main.nu`, so the compile gate returns success without
compiling anything — `every gate passed` on a library means the manifest
and the imports agree, not that the code builds. Run `nurlpkg test`
against a library before publishing it.

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
