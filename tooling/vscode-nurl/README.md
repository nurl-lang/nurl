# NURL Language Extension

Syntax highlighting for **NURL** (Neural Unified Representation Language) in VS Code and Windsurf.

## Features

- Syntax highlighting for `.nu` files
- Comment toggling (`//`)
- Bracket matching and auto-closing
- Highlights:
  - Functions (`@ name`)
  - Function calls (`( fn args )`)
  - Types (`i u f b s v` and named types)
  - Operators (`→ ^ ?? ? ~ ; \\ Z` etc.)
  - Strings (backtick-delimited)
  - Numbers and booleans (`T`/`F`)

## Installation

### From VSIX file

1. Download `nurl-0.1.0.vsix`
2. In VS Code/Windsurf: `Ctrl+Shift+P` → "Extensions: Install from VSIX..."
3. Select the downloaded file

### Manual

Copy the extension folder to:
- **VS Code**: `~/.vscode/extensions/nurl`
- **Windsurf**: `~/.windsurf/extensions/nurl`

## Release Notes

### 0.1.0

Initial release with syntax highlighting for NURL.
