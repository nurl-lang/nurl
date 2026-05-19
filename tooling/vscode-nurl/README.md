# NURL Language Extension

Editor support for **NURL** (Neural Unified Representation Language) in
VS Code and Windsurf.

## Features

* Syntax highlighting for `.nu` files
* Comment toggling (`//`)
* Bracket matching and auto-closing
* **Language Server** (`nurl-lsp`, v0.4.4+):
  * Live compile-error / warning diagnostics on save and on type
  * Document tracking via `textDocumentSync` (full sync)
  * **Go-to-definition** — `gf` / `F12` jumps from a call site or
    type reference to the `@`-fn, `:`-struct, `: |`-enum, enum
    variant, or `& \`lib\` @`-FFI decl. Resolves across files
    through `$ \`path\`` import edges (transitively indexed).
  * **Hover** — function signature, type name, or constant value
    snapshot for any IDENT under the cursor.
  * **Document outline** — `Ctrl-Shift-O` lists every top-level
    decl with its source line and SymbolKind (Function/Struct/
    Enum/EnumMember/Constant).
  * **Completion** — IDENT-prefix completion across the indexed
    workspace; kind-tagged so the editor renders the right icon.
  * **Workspace symbol search** — `Ctrl-T` case-insensitive
    substring match against every indexed decl.
  * **Folding ranges** — brace-balanced + `// ──` banner-comment
    folds.
  * **Formatting** — `textDocument/formatting` shells out to
    `nurlfmt` for canonical NURL formatting.

## Setup

**Recommended (one command):**

```bash
git clone https://github.com/nurl-lang/nurl.git
cd nurl
./install.sh                     # bootstrap, build LSP, install ext
```

`install.sh` is idempotent — re-run any time to pick up a newer
checkout. It bootstraps the compiler if needed, builds `nurl-lsp`,
copies it to `~/.local/bin/`, packages the VS Code extension, and
installs it via the `code` (or `windsurf`) CLI when one is on PATH.

**Manual:**

```bash
./build.sh                       # bootstrap the compiler
./tools/nurl-lsp/build.sh        # build the LSP server
```

This produces `build/nurl-lsp`. When you open a `.nu` file in a
workspace whose root contains that file, the extension finds it
automatically.

To point at a different binary:

```jsonc
// settings.json
"nurl.server.path": "/absolute/path/to/nurl-lsp"
```

Or place `nurl-lsp` on `$PATH`.

### Server fallback order

1. `nurl.server.path` setting (workspace or user)
2. `<workspaceFolder>/build/nurl-lsp`
3. `nurl-lsp` on `$PATH`

If none resolves to an executable, the extension surfaces a warning
notification once and falls back to **syntax-only mode** — bracket
matching and highlighting keep working independently of the LSP.

## Installation

### From VSIX file

1. Build the `.vsix`:

   ```bash
   cd tooling/vscode-nurl
   npm install
   npx vsce package
   ```

2. In VS Code / Windsurf: `Ctrl+Shift+P` → "Extensions: Install from
   VSIX..." → pick the newly built `nurl-0.4.4.vsix`.

### Manual development install

Symlink the extension folder into your editor's extensions directory:

* **VS Code**: `~/.vscode/extensions/nurl`
* **Windsurf**: `~/.windsurf/extensions/nurl`

Then run `npm install` inside that folder so the
`vscode-languageclient` dependency is fetched.

## Troubleshooting

* **"nurl-lsp binary not found"** notification: the extension couldn't
  resolve the binary. Either build it (see *Setup*) or set
  `nurl.server.path` to an absolute location.
* **Diagnostics don't update**: open the *Output* panel and switch to
  *NURL Language Server* to see the raw stderr from `nurl-lsp` and
  the LSP message trace (enable
  `"nurl.server.trace": "messages"` in settings).
* **Compile errors point at the wrong location**: NURL diagnostics
  use 1-based line/column and prefix-notation, which the extension
  translates to LSP's 0-based positions. The caret position is the
  one the compiler emits — see [`docs/GOTCHAS.md`] item 4 for why
  prefix-arity errors sometimes report the wrong line.

## Release Notes

### 0.4.4

* Server feature set documented to match reality: go-to-definition
  (single + cross-file via `$ `path``), hover, document outline,
  completion, workspace symbol search, folding ranges, and
  `nurlfmt`-backed formatting are all live. Version bumped to
  match the `nurl-lsp` server it pairs with. Recommended install
  path is now the top-level `./install.sh`.

### 0.3.0

* Language Server client added. Live diagnostics from the NURL
  compiler stream into the editor as you type.

### 0.2.0

Polished grammar, bug fixes.

### 0.1.0

Initial release with syntax highlighting.
