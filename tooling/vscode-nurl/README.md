# NURL Language Extension

Editor support for **NURL** (Neural Unified Representation Language) in
VS Code and Windsurf.

## Features

* Syntax highlighting for `.nu` files
* Comment toggling (`//`)
* Bracket matching and auto-closing
* **Language Server** (`nurl-lsp`, v0.4.1+):
  * Live compile-error / warning diagnostics on save and on type
  * Document tracking via `textDocumentSync` (full sync)
  * Go-to-definition, hover, document outline, completion: coming
    in later iterations

## Setup

The Language Server is a separate native binary (`build/nurl-lsp`)
that the extension launches over stdio. Build it once:

```bash
git clone https://github.com/nurl-lang/nurl.git
cd nurl
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
   VSIX..." → pick the newly built `nurl-0.3.0.vsix`.

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

### 0.3.0

* Language Server client added. Live diagnostics from the NURL
  compiler stream into the editor as you type.

### 0.2.0

Polished grammar, bug fixes.

### 0.1.0

Initial release with syntax highlighting.
