# Change Log

All notable changes to the "nurl" extension will be documented in this file.

Check [Keep a Changelog](http://keepachangelog.com/) for recommendations on how to structure this file.

## [0.3.0] — 2026-05-16

### Added

- **Language Server client**. The extension now spawns the
  `nurl-lsp` binary over stdio via `vscode-languageclient` and
  surfaces diagnostics (errors + warnings) live as you type. Server
  binary is resolved in order: `nurl.server.path` setting →
  `<workspaceFolder>/build/nurl-lsp` → PATH lookup for `nurl-lsp`.
  When no binary is found, the extension stays in syntax-only mode
  and shows a one-shot notification with build instructions.

### Configuration

- `nurl.server.path` — absolute path override
- `nurl.server.trace` — `off` / `messages` / `verbose` to log the
  LSP wire to the Output channel

## [0.2.0] — 2026-05-14

Catches the grammar up from v1.1-era highlighting (where `0.1.0`
shipped) to the current v1.8 surface.

### Added

- **Fixed-size primitive types** highlighted as
  `storage.type.primitive.sized.nurl` (grammar v1.8): `i8`, `i16`,
  `i32`, `u16`, `u32`, `u64`, `f32`. They must be listed before the
  single-letter pattern so `i8` doesn't get partially captured as
  the bare `i`.
- **Shift operators** `<<` and `>>` highlighted as
  `keyword.operator.shift.nurl` (grammar v1.4). Listed before the
  comparison-operator rule so `<<` is not mis-classified as two
  `<` tokens.
- **`\r` escape sequence** recognised inside backtick strings
  alongside the existing `\n`, `\t`, `\\` (grammar v1.3 — CRLF
  support for HTTP/SMTP literals).

### Changed

- **Numeric literals match the negative-literal lexer rule**
  (grammar v1.1): a `-` immediately followed by a digit with no
  intervening whitespace is part of the literal. The integer and
  float regexes now allow a leading `-?`, anchored on a
  non-identifier prefix so binary minus (`- a b`) keeps its
  per-token highlighting.

## [0.1.0]

- Initial release