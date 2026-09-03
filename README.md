# NURL — Neural Unified Representation Language

> A small systems language with a regular prefix-arity grammar, single-owner memory with a default-on static borrow checker, deterministic compilation, and LLVM-based codegen.

**Project site:** <https://nurl-lang.org> · **Live playground & MCP endpoint:** <https://play.nurl-lang.org>

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/gist/Hindurable/b2b5641328d23097048eef22bcac4a2d/nurl.ipynb)

---

## Why NURL?

NURL takes a few design positions that are uncommon together:

- **Regular prefix-arity grammar** — every operator has a fixed arity, no infix, no precedence cliffs. The grammar fits on a single page and is LL(k≤4) — recursive-descent with up to 4 tokens of lookahead.
- **Locally parseable** — a construct's shape (arity and nesting) is fixed by a short window of surrounding tokens, with no long-range parse dependencies. (A few operators — `.`, `&`, `|`, `#` — resolve their *lowering* by operand type; see [`docs/spec.md`](docs/spec.md) §4.9/§6.)
- **Deterministic compiler** — the same source always produces identical output, with no platform-dependent codegen. The self-hosted compiler reaches a byte-identical fixed point on its own source. (Raw `*T` pointers and out-of-range shifts inherit LLVM semantics — spec §4.2, §6.1.)
- **Single-owner memory + default-on static borrow checker** — auto-drop at scope exit, plus a diagnostic pass (on by default, `--no-borrowck` to disable) that catches use-after-move, alias-double-free, escaping closure-captures, and iterator invalidation as hard errors.
- **Diagnostics that name the cure** — an error states what was expected, what was found, and the correct form with an example, because for a model the compiler is the only teacher in the loop. 170 of the compiler's 173 error sites carry an explanation — the messages do the work a gotchas document used to.
- **LLVM-based codegen, broad platform reach** — one pipeline targets Linux, macOS, Windows, wasm32-wasi, RISC-V, and ARM64 — and a NURL program can **boot as its own kernel**: bootable unikernel images (no host OS, no libc) on x86_64, AArch64 and RISC-V64. See [`unikernel/README.md`](unikernel/README.md).

A reproducible benchmark suite lives in [`bench/`](bench/): 15 benchmarks
implemented five times each — NURL, C, Rust, Node and Python — with every row
gated on all five printing the same result before any of them is timed.
`bench/bench.sh` runs the lot and writes [`bench/RESULTS.md`](bench/RESULTS.md)
(run times, compile times, correctness gate, process-start-up floor) plus a
machine-readable `bench/results/latest.json`, which is what nurl-lang.org
renders its table from. The
[`bench` workflow](.github/workflows/bench.yml) refreshes both weekly on a
fixed CI runner. Numbers are machine-specific, so run the suite locally for
figures you can trust. The HTTP-server peer benchmarks are separate:
[`bench/HTTP_RESULTS.md`](bench/HTTP_RESULTS.md) (HTTP/1.1),
[`bench/HTTP2_RESULTS.md`](bench/HTTP2_RESULTS.md) (HTTP/2) and
[`bench/HTTP3_RESULTS.md`](bench/HTTP3_RESULTS.md) (HTTP/3 over QUIC).

---

## Design principles

1. **Regular grammar** — no exceptions; the same construct always works the same way.
2. **Local structure** — a construct's shape derives from a short window of tokens, no long-range parse dependencies.
3. **Deterministic compiler** — same source → identical output, no platform variation.
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

### Install the toolchain

Prebuilt `nurlc` / `nurlpkg` / `nurlfmt` binaries, one command — no clang, no
build:

```bash
# Linux / FreeBSD  (macOS: build from source — see Building)
curl -fsSL https://nurl-lang.org/install.sh | sh
```

```powershell
# Windows (PowerShell)
irm https://nurl-lang.org/install.ps1 | iex
```

Then:

```bash
nurlpkg install <name>     # fetch & build a program from reg.nurl-lang.org
nurl --version             # what you have
nurl upgrade               # move to the newest release, in place
```

`nurl upgrade` keeps everything else in `~/.nurl` — your registry token, the
model cache, and every program installed with `nurlpkg install`. (Aliases:
`nurl update`, `nurlpkg self-update`. Not `nurlpkg update` — that one is
about a project's dependencies.)

### Build from source

For contributors, or to run the bootstrap yourself:

```bash
git clone https://github.com/nurl-lang/nurl.git
cd nurl
./build.sh                                            # builds the C runtime, bootstraps, runs tests
./nurl.sh examples/fizzbuzz.nu fizzbuzz && ./fizzbuzz # compile & run a program
```

The only build-time dependency is **clang / LLVM 15+**. `./install.sh` also
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
mutation with `: ~`). A **static borrow checker** — on by default,
`--no-borrowck` to disable, `--strict-borrowck` to tighten — catches
use-after-move, alias-double-free, escaping closure-captures, and iterator
invalidation as hard compile errors, without ever changing generated code.
The one remaining source-level trap, the n-ary `&`/`|` foot-gun, is a
hard error by default; `--no-strict-arity` demotes it to a warning for
trees that need to keep building.
Full model and the not-yet-checked list: [`docs/MEMORY.md`](docs/MEMORY.md).

The type system is strong, static, inferred, algebraic (sum types `|`,
product types via structs), with no subtyping and no implicit conversions.

---

## Testing & CI

Every push and PR that touches code runs the bootstrap fixed point and the
full test corpus on **four host platforms and one bare-metal target**, not
one:

| Gate | Where | What it proves |
|---|---|---|
| Linux x86_64 | `ubuntu-latest` | Fixed point + full corpus, `examples/` frontend gate, `nurlfmt` canonical-format gate, and ~20 targeted gates (CRC-32, XXH64, Zstandard against the `zstd` CLI, DWARF, HTTP per-request leak, HTTP/2 conformance with h2spec, HTTP/3 + QUIC conformance with h3spec, diagnostic coverage) |
| FreeBSD 14.2 | real VM | The same corpus on a second OS |
| **Windows x86_64** | `windows-latest` | `build.bat` fixed point + the Windows golden corpus, then `nurl.bat` builds and runs a program with both the bundled zig and clang |
| **macOS ARM64** | `macos-14` (Apple Silicon) | `./build.sh` stage1 ≡ stage2 fixed point + the full corpus against the **same goldens as Linux**, plus the `examples/` gate |
| **Unikernel** | QEMU, in CI | The corpus with no libc at all, then the guest booted on x86_64, AArch64 **and** RISC-V64 — plus the PVH image under cloud-hypervisor |
| Sanitizers | `ubuntu-latest` | The whole corpus under AddressSanitizer + UndefinedBehaviorSanitizer |

The second OS and the two non-Linux hosts keep the toolchain honest — the
shipped `nurlc` / `nurlpkg` binaries link only libc and `nurl.sh` is POSIX
`sh`, so the toolchain runs unmodified on glibc, musl / Alpine, BSD, Windows
and macOS. A documentation-only PR (`webdocs/**`) skips the code gates and
runs the docs build instead; a PR touching both runs everything. Gate list
and how to reproduce each locally:
[`docs/BUILDING.md`](docs/BUILDING.md#continuous-integration).

---

## Tooling

One `curl | sh` installs the toolchain — `nurlc`, `nurlpkg`, `nurlfmt` and
the `nurl` build wrapper. `nurlpkg install <name>` fetches, builds, and
installs programs from the registry at
[reg.nurl-lang.org](https://reg.nurl-lang.org). The rest is one command
away: `nurl-lsp` + the VS Code extension come with a source checkout's
`./install.sh`; `nurlpkg install nurl-mcp` drives the local toolchain from
an LLM agent over MCP; `nurlpkg install wasmbuilder` compiles NURL to
wasm32-wasi locally and `nurlpkg install nwasm` runs it with a
pure-NURL runtime. Details: [`docs/TOOLING.md`](docs/TOOLING.md).

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
| Async runtime (fibers) | [`docs/ASYNC.md`](docs/ASYNC.md) |
| Networking & MQTT client | [`docs/NETWORKING.md`](docs/NETWORKING.md) |
| Cryptography & TLS (pure-NURL, no OpenSSL) | [`docs/CRYPTO.md`](docs/CRYPTO.md) |
| Distributed stack (NAT traversal, overlay, SWIM, CRDTs) | [`docs/DISTRIBUTED.md`](docs/DISTRIBUTED.md) |
| HTTP API, playground & MCP server | [`docs/PLAYGROUND.md`](docs/PLAYGROUND.md) |
| Platforms — codegen targets & host OSes (incl. FreeBSD) | [`docs/PLATFORMS.md`](docs/PLATFORMS.md) |
| Unikernel — a NURL program as its own kernel | [`unikernel/README.md`](unikernel/README.md) |
| Known limitations | [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md) |
| Compiler internals (for contributors) | [`docs/dev/COMPILER_INTERNALS.md`](docs/dev/COMPILER_INTERNALS.md) |
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
│   └── runtime.o, …      — runtime objects (build outputs of build.sh)
├── examples/               — curated .nu programs (see examples/README.md)
├── nurlapi/                — NURL-native container: compiler-as-a-service + playground + MCP
├── unikernel/              — bootable unikernel images (x86_64 / AArch64 / RISC-V64)
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
