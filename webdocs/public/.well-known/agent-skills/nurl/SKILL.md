---
name: nurl
description: Write, check and build programs in NURL, a compiled prefix-notation language (.nu files) that lowers to LLVM IR. Use when a task asks for NURL code, touches .nu files, or needs a NURL program built for Linux, Windows, macOS, WebAssembly, RISC-V/ARM64 or a unikernel.
---

# Writing NURL

NURL is terse, prefix-notation and unlike any language you were trained on
at length. Do not write it from memory: read the reference, copy the shape
of a working example, and let the compiler check every draft.

## 1. Get the reference into context

- Language reference / cheat sheet: https://nurl-lang.org/docs/cheat-sheet.md
- Common pitfalls (read before the first draft): https://nurl-lang.org/docs/common-pitfalls.md
- Every docs page as Markdown: https://nurl-lang.org/llms.txt (index) or
  https://nurl-lang.org/llms-full.txt (all pages in one file)
- The grammar (EBNF): https://github.com/nurl-lang/nurl/blob/main/spec/grammar.ebnf

## 2. Use the NURL MCP server when you can

The hosted MCP server needs no auth and no local toolchain:

```bash
claude mcp add --transport http nurl https://play.nurl-lang.org/mcp
```

Its tools:

- `nurl_read_grammar`, `nurl_read_readme`, `nurl_docs` — the spec and prose docs
- `nurl_list_examples` / `nurl_read_example`, `nurl_list_stdlib` / `nurl_read_stdlib`,
  `nurl_api` (a module's signatures), `nurl_grep` — find working code to copy
- `nurl_build_native`, `nurl_build_wasm`, `nurl_build_windows`, `nurl_build_macos`,
  `nurl_build_target`, `nurl_build_unikernel` — compile; each returns the
  compiler diagnostics as `{file, line, col, severity, message}` and a
  download URL for the binary
- `nurl_changelog`, `nurl_read_roadmap` — whether a feature exists yet

Without MCP, the same build endpoints are plain HTTP:
https://play.nurl-lang.org/openapi.json (OpenAPI 3.1). The hosted service is
public and unauthenticated: never send secrets in source code.

## 3. The loop

1. Find the closest example or stdlib module (`nurl_grep`, `nurl_list_examples`)
   and read it before writing.
2. Write the smallest program that compiles, then grow it.
3. Compile after every change. Locally: `nurl --check file.nu` for a fast
   parse, type and borrow check; `nurl --run file.nu` to build and run.
   Remotely: `nurl_build_native` or `nurl_build_wasm`.
4. Fix the first diagnostic, not all of them; later ones are often fallout.
5. Before you finish, run the program and compare its output with what the
   task asked for.

## 4. Mistakes everyone makes first

- Calls always need parentheses: ``( nurl_print `hello` )``. A bare name is a
  lookup, not a call.
- `^` is return; XOR is `^^` (no space between the carets).
- Struct parameters are copies; declare a parameter `inout` to change the
  caller's value.
- `i u f b s v` are type keywords, not variable names.
- Use `Arc`, not `Rc`, for anything a thread or fiber shares.

## Install a local toolchain

```bash
curl -fsSL https://nurl-lang.org/install.sh | sh
```

Windows: `irm https://nurl-lang.org/install.ps1 | iex`. Guide:
https://nurl-lang.org/docs/install.md
