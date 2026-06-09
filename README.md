# NURL — Neural Unified Representation Language

> A small systems language with a regular prefix-arity grammar, single-owner memory with an opt-in static borrow checker, deterministic compilation, and LLVM-based codegen.

**Project site:** <https://nurl-lang.org> · **Live playground & MCP endpoint:** <https://play.nurl-lang.org>

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/gist/Hindurable/b2b5641328d23097048eef22bcac4a2d/nurl.ipynb)

---

## Why NURL?

NURL takes a few design positions that are uncommon together:

- **Regular prefix-arity grammar** — every operator has a fixed arity, no infix, no precedence cliffs. The grammar fits on a single page and is LL(k≤4) — recursive-descent with up to 4 tokens of lookahead.
- **Local semantics** — a construct's meaning is derivable from a short window of surrounding tokens. No long-range dependencies.
- **Deterministic compiler** — the same source always produces identical output. No UB, no platform-dependent behaviour. The self-hosted compiler reaches a byte-identical fixed point on its own source.
- **Single-owner memory + opt-in static borrow checker** — auto-drop at scope exit, plus a diagnostic pass that catches use-after-move, alias-double-free, escaping closure-captures, and iterator invalidation as hard errors.
- **LLVM-based codegen, broad platform reach** — one pipeline targets Linux, macOS, Windows, wasm32-wasi, RISC-V, and ARM64.

| Metric | Python | C | NURL |
|---|---|---|---|
| Grammar productions | ~100 | ~200 | ~50 |
| Runtime performance | slow | fast | fast (LLVM) |
| Target platforms | one | many | any LLVM target |

A reproducible micro-benchmark suite lives in [`bench/`](bench/) — `bench/run.sh`
compiles and runs one source file per language N times and prints a median-ms
table. Captured numbers (compute and HTTP-server peer benchmarks) are in
[`bench/RESULTS.md`](bench/RESULTS.md) and [`bench/HTTP_RESULTS.md`](bench/HTTP_RESULTS.md);
they are machine-specific, so run the suite locally for figures you can trust.

---

## Design principles

1. **Regular grammar** — no exceptions; the same construct always works the same way.
2. **Local semantics** — meaning derives from a short window of tokens, no long-range dependencies.
3. **Deterministic compiler** — same source → identical output, no UB, no platform variation.
4. **Full platform support** — one compilation pipeline → every LLVM target without porting.

---

## Architecture

```
NURL source (.nu)
        │
        ▼
   Tokenizer  (deterministic, context-free)
        │
        ▼
     Parser   (LL(k≤4), ≤4-token lookahead)
        │
        ▼
   LLVM IR (.ll)
        │
        ▼
      clang
        │
   ┌────┴────────────┐
   ▼                 ▼
native            wasm32-wasi
(Linux/Win/macOS) (via WASI SDK)
```

The compiler (`compiler/nurlc.nu`) is written in NURL itself. The bootstrap
runs it twice over its own source and requires byte-identical LLVM IR on both
rounds before the build is accepted. Details: [`docs/BUILDING.md`](docs/BUILDING.md).

---

## Quick start

```bash
git clone https://github.com/nurl-lang/nurl.git
cd nurl
clang -c stdlib/runtime.c -o stdlib/runtime.o   # once (already checked in)
./build.sh                                       # bootstrap + test suite
./nurl.sh examples/fizzbuzz.nu && ./fizzbuzz     # compile & run a program
```

The only build-time dependency is **clang / LLVM 14+**. `./install.sh` also
sets up the editor extension and language server in one step. Full instructions
— prerequisites per OS, manual bootstrap, DWARF debugging — are in
[`docs/BUILDING.md`](docs/BUILDING.md); editor/LSP/formatter setup is in
[`docs/TOOLING.md`](docs/TOOLING.md).

---

## Syntax at a glance

NURL uses **prefix notation** — the structure is always `OP ARG1 ARG2 … ARGN`.
Types are single letters (`i` int64, `u` byte/uint8, `f` float64, `b` bool,
`s` string, `v` void, `*T` pointer; sized variants `i8`/`i16`/`i32`,
`u16`/`u32`/`u64`, `f32`); operators are sigils (`:` bind, `=`
assign, `@` define, `→` arrow, `.` member, `?` ternary/option, `??` match,
`~` loop/mutability, `!` not/Result, `\` closure/try, `^` return, `#` cast,
`%` trait, `$` import).

```
: | Json { JNull  JBool b  JNum i  JStr s }

@ describe Json v → s {
  ^ ?? v {
      JNull   → `null`
      JBool x → ? x `true` `false`
      JNum n  → ( nurl_str_int n )
      JStr s  → s
    }
}
```

Calls always need parens — `( fn args )` is the only call form; a bare
identifier is a name lookup. The **authoritative grammar** is
[`spec/grammar.ebnf`](spec/grammar.ebnf) and the **normative language
reference** (lexical structure, types, statements, expressions, casts) is
[`docs/spec.md`](docs/spec.md).

---

## Memory & safety

Single-owner memory with compiler-inserted auto-drop at scope exit — no GC,
no hidden boxing. Bindings are immutable by default (`: i x 0`; opt into
mutation with `: ~`). An **opt-in static borrow checker** (on by default,
`--no-borrowck` to disable) catches use-after-move, alias-double-free,
escaping closure-captures, and iterator invalidation as hard compile errors,
without ever changing generated code. Full model and the not-yet-checked
list: [`docs/MEMORY.md`](docs/MEMORY.md).

The type system is strong, static, inferred, algebraic (sum types `|`,
product types via structs), with no subtyping and no implicit conversions.

---

## Documentation

| Topic | Document |
|---|---|
| Language reference (normative) | [`docs/spec.md`](docs/spec.md) |
| Grammar (authoritative) | [`spec/grammar.ebnf`](spec/grammar.ebnf) |
| Building, bootstrap & debugging | [`docs/BUILDING.md`](docs/BUILDING.md) |
| Tooling — editor / LSP / formatter / package manager | [`docs/TOOLING.md`](docs/TOOLING.md) |
| Canonical source format (`nurlfmt`) | [`docs/FORMAT.md`](docs/FORMAT.md) |
| Memory model & borrow checker | [`docs/MEMORY.md`](docs/MEMORY.md) |
| Async runtime (fibers) design | [`docs/ASYNC.md`](docs/ASYNC.md) |
| Networking & MQTT client | [`docs/NETWORKING.md`](docs/NETWORKING.md) |
| HTTP API, playground & MCP server | [`docs/PLAYGROUND.md`](docs/PLAYGROUND.md) |
| Target platforms | [`docs/PLATFORMS.md`](docs/PLATFORMS.md) |
| Known limitations | [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md) |
| Gotchas (compiler-diagnosed) | [`docs/GOTCHAS.md`](docs/GOTCHAS.md) |
| Examples catalogue | [`examples/README.md`](examples/README.md) |
| Roadmap · Changelog · Contributing | [`ROADMAP.md`](ROADMAP.md) · [`CHANGELOG.md`](CHANGELOG.md) · [`CONTRIBUTING.md`](CONTRIBUTING.md) |

**Why this matters for LLMs:** the regular grammar makes generation reliable
and errors local, a whole program fits in a context window, and diffs stay
small. The concrete vehicle is the public MCP server at
<https://play.nurl-lang.org/mcp> — see [`docs/PLAYGROUND.md`](docs/PLAYGROUND.md).

---

## Project layout

```
nurl/
├── spec/grammar.ebnf       — authoritative grammar (versioned snapshots alongside)
├── compiler/
│   ├── nurlc.nu            — self-hosting compiler, written in NURL
│   ├── nurlc_lastgood.{nu,ll} — committed bootstrap snapshot (source + IR)
│   └── tests/             — .nu test programs + snapshot runner + golden baseline
├── stdlib/
│   ├── runtime.c           — C runtime (I/O, string helpers, FFI surface)
│   ├── core/ std/ ext/     — the NURL standard library
│   └── runtime{.o,.wasm.o} — native and wasm32-wasi runtime builds
├── examples/               — curated .nu programs (see examples/README.md)
├── nurlapi/                — NURL-native container: compiler-as-a-service + playground + MCP
├── tooling/vscode-nurl/    — editor extension (syntax + LSP client)
├── tools/                  — nurl-lsp, nurlfmt, nurlpkg build scripts
├── docs/                   — topic documentation (see the table above)
├── bench/                  — reproducible benchmark suite
├── build.sh / build.bat    — full bootstrap + test-suite driver
└── nurl.sh  / nurl.bat     — compile a .nu file
```

---

## Name

**NURL** = **N**eural **U**nified **R**epresentation **L**anguage. File
extension: `.nu`.

---

## License

Copyright (c) 2026 The NURL Project Developers. Dual-licensed under either of
[MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE) at your option. SPDX
identifier: `MIT OR Apache-2.0`.

Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in the work by you, as defined in the Apache-2.0
license, shall be dual-licensed as above, without any additional terms or
conditions.
