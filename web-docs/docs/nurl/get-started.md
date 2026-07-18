---
outline: deep
title: Start with NURL
order: 1
---

# Introduction

::: warning Work In Progress
NURL web documentation is maintained separately. For up-to-date information refer to the repository documentation in [docs.](https://github.com/nurl-lang/nurl/tree/main/docs)
:::

**NURL** is a compiled language without a virtual machine, garbage collector and interpreter. `.nu` files are compiled straight to a native excecutable or a WebAssembly module.

## Features of NURL

NURL is **designed** to be a target for **LLM code generation** specifically. The regular grammar means errors stay local and a whole program fits predictably in a context window.

> comment: following sec. needs better clarification

- **Prefix-arity grammar** -- every construct has a fixed arity and there’s no infix/precedence table to learn. This is easier to parse for the AI and results in lower token usage. The grammar fits on one page and parses with at most 4 tokens of lookahead (LL(k≤4)).
- **Reproducible builds** (deterministic compilation) -- same source produces byte-identical output on every supported platform.
- **Single-owner memory** -- values auto-drop at scope exit.
- **Static borrow checker** -- rejects use-after-move, alias-double-free, escaping closure-captures, and iterator invalidation at compile time.
- **One LLVM pipeline** -- the same codegen path targets Linux, macOS, Windows, wasm32-wasi, RISC-V, and ARM64 without per-platform ports.


## State of NURL <Badge type="tip" text="pre-release" />

NURL is actively developed and is now in pre-stable release state. see [`ROADMAP.md`](https://github.com/nurl-lang/nurl/blob/main/ROADMAP.md) for the latest version.

Major changes are currently less frequent and the stable release is aimed for late 2026.

## Requirements

- Only clang / LLVM 15 or newer if you’re building from source

## Get NURL

1. **[Installation](./install.md)** — The `nurlc` compiler (and the
   `nurlpkg` / `nurlfmt` tools)
2. **First program** — write and understand
   a minimal "hello world"
3. **[Compiling and running](./compiling-and-running.md)** — the compile
   pipeline, the `nurl` wrapper, and useful flags.
4. **[Next steps](./next-steps.md)** — The
   language guide, the standard library, the examples folder, and the
   online playground.