# NURL Roadmap

This roadmap describes where NURL is **today** and where it is going. It is
forward-looking and deliberately concise — the full, reverse-chronological
record of *what shipped when* lives in [`CHANGELOG.md`](CHANGELOG.md).
Anything marked done here has a regression test in
[`compiler/tests/`](compiler/tests/) and is covered by the bootstrap fixed
point.

_Last reviewed: 2026-06-26 · Current release: **0.10.0** · Language: **Grammar
v2.2** ([`spec/grammar.ebnf`](spec/grammar.ebnf))._

---

## Status at a glance

NURL is a small systems language with a regular prefix-arity grammar, a
self-hosted compiler written in NURL, and an LLVM backend. The compiler
bootstraps to a **byte-identical fixed point** on its own source (stage1 ≡
stage2). The only build dependency is clang / LLVM 15+.

What is solid today:

- **Language (Grammar v2.2).** Sum types (`|`) and product types (structs),
  generics over structs and functions (incl. generics over option/result
  types), pattern matching with **match guards**, **or-patterns**, and
  **N-ary payloads**, **trait bounds** on type parameters (`[A: Ord]`), **compile-time constant
  folding** (`const_eval_int`), a full numeric type set (`i` = i64 and
  `u` = byte/u8, plus sized `i8`/`i16`/`i32`, `u16`/`u32`/`u64`, `f` = f64
  and `f32`), tail-call optimization, and
  **variadic FFI** (the `printf` family callable directly). The grammar decision
  for prefix-arity (no grouping delimiter) is formally locked.
- **Memory & safety.** Single-owner memory with compiler-inserted auto-drop at
  scope exit — no GC, no hidden boxing. A **static borrow checker, on
  by default** (`--no-borrowck` to disable, `--strict-borrowck` to tighten),
  catches use-after-move, alias double-free, escaping closure captures,
  interprocedural/return escape, loop-carried double-frees, and
  iterator invalidation as hard errors without changing generated code.
- **Concurrency.** A stackful M:N work-stealing async runtime with **no
  `async`/`await` colouring** — ordinary code runs unchanged under the
  scheduler — plus threads/mutex/cond, typed channels, and Go-style `??`
  channel **select**.
- **Standard library.** A broad pure-NURL stdlib (see the inventory below)
  spanning collections, hashing, serialization, a full HTTP/1.1+2 + WebSocket
  stack, database clients, distributed systems (p2p overlay, CRDTs), MCP, and the Anthropic Claude API.
- **Targets.** Linux x86_64 (primary), Windows x86_64, macOS x86_64/ARM64,
  `wasm32-wasi`, and static Linux ARM64 / RISC-V64 (musl). See
  [`docs/PLATFORMS.md`](docs/PLATFORMS.md).
- **Tooling.** `nurlc` (compiler), `nurlfmt` (canonical formatter), `nurl-lsp`
  (language server), `nurlpkg` (package manager + test/bench runner), `nurldoc`
  (API-doc generator), `tools/repl`, DWARF debug info (`--g`), a
  VS Code extension, and `nurlapi` — a compiler-as-a-service container that
  powers the public playground and MCP endpoint.

The path to **1.0** is hardening, documentation precision, and external
validation rather than new language surface — see *Toward 1.0* below.

---

## Shipped

A high-level map of what exists. Dates and per-feature detail are in
[`CHANGELOG.md`](CHANGELOG.md).

### Compiler & language

- Self-hosted compiler (`compiler/nurlc.nu`) with a deterministic, byte-identical
  bootstrap; stage-0 links the committed `nurlc_lastgood.ll` snapshot (no
  Python in the toolchain).
- Grammar evolved v0.1 → **v2.2** (snapshots in [`spec/`](spec/)). v2.x added:
  visibility (`pub`) enforcement across functions, types, consts, and enum
  variants; trait bounds; match guards + or-patterns; const folding; channel
  select; and locked the prefix-arity grouping decision.
- Type system: strong, static, inferred, algebraic; no subtyping, no implicit
  conversions. Sized integer/float types with signedness tracking; explicit
  `#` casts with correct `sext`/`zext`/`trunc`/`fpext`/`fptrunc`.
- Generics: monomorphised generic structs and functions (signedness-aware), generic nesting
  (`Channel[A]`, `Vec[Thread]`), and generics over `?T` / `!T E`.
- Memory model: auto-drop, recursive `Drop` for boxed enum/struct payloads,
  `% Drop` user destructors, move/borrow analysis (incl. interprocedural and
  loop-carried escape detection). Model and known gaps:
  [`docs/MEMORY.md`](docs/MEMORY.md).
- Front-end is diagnostic-first: malformed prefix-arity programs, undefined
  identifiers, call-arity mismatches, unbalanced braces / stray top-level
  tokens, and visibility violations are hard errors with source locations —
  nothing malformed reaches the backend silently.
- Debugging: DWARF emission (`nurlc --g`) with `ptype`/`print` over structs.

### Standard library

Organised as `core/` (language essentials), `std/` (general-purpose), and
`ext/` (external-format / network / service bindings). All pure NURL except a
small C runtime (`stdlib/runtime.c`) for the bootstrap surface and a few
platform-specific shims.

- **core** — `string`, `vec`, `option`, `result`, `errors`, `char`, `slice`,
  `pair`, `box`, `cell`, `mem`, `io`, `symtab`, `posix`.
- **std/collections & algorithms** — `hashmap`, `set`, `deque`, `heap`,
  `ordmap`, `btree`, `lru`, `bitset`, `iter`, `sort`, `cmp`, `bytes`, `bufio`, `fmt`, `int`, `float`,
  `bigint` (arbitrary-precision integers), `decimal` (exact fixed-point).
- **std/runtime services** — `async`, `thread`, `channel`, `arc`, `rc`,
  `arena`, `signal`, `panic`/`recover`, `process`, `unixsock` (local IPC),
  `log` (text + JSON), `time` (incl. timezone/DST, HTTP/RFC 2822 dates), `args` (CLI parser),
  `term` (POSIX termios, ANSI).
- **std/crypto & encoding** — `hash` (SHA-1/256/512, MD5, HMAC),
  `hash_blake3`, `encode` (hex, base64, base32), `random` (OS CSPRNG),
  `rng` (seedable, deterministic xoshiro256\*\*).
- **std/IO & net** — `fs` (incl. streaming + `readlink`), `path` (typed),
  `net` (TCP/TLS), `udp`, `dns`, `dos`.
- **ext/serialization** — `json`, `toml`, `csv`, `msgpack`, `cbor`, `xml`, `yaml`,
  `serde`, `regex`.
- **ext/web stack** — full HTTP/1.1 server (keep-alive, pipelining, static,
  auth, JWT bearer-auth, cookies, forms, multipart, router, middleware, access log + Prometheus
  metrics, DoS caps, graceful shutdown, per-request timeouts, panic recovery),
  HTTP client (with cookie jar), **TLS** (SNI + ALPN + mTLS + live cert reload), **HTTP/2**
  (RFC 9113 + HPACK, **server and client**), **WebSocket** (RFC 6455, **server
  and client**, with **permessage-deflate** compression — RFC 7692),
  reverse proxy with binary-safe streaming. The stack has had a
  dedicated security-hardening pass (path-traversal, SSRF, request-smuggling,
  HTTP/2 CONTINUATION-flood + stream-accounting, and clean cross-thread
  listener shutdown) with regression tests.
- **ext/data services** — `sqlite` (production-hardened), `postgres` (binary
  protocol, async, LISTEN/NOTIFY, COPY), `mqtt` 5.0 client, `smtp` (mail submission).
- **ext/AI & agents** — `mcp` (+ `client`, `http`, `session`, `stdio`,
  `registry`) and `anthropic` (Claude Messages API incl. streaming SSE +
  tool-use deltas).
- **ext/packaging** — `semver`, `manifest`, `lockfile`, `resolver`,
  `registry_index`, `pkg_fetch`, `pkg_publish` (the `nurlpkg` backend).
- **ext/misc** — `compress` (zlib/zstd/gzip), `zip` (archives), `tar`, `uuid` (v4/v7),
  `credentials`, `env`.
- **dist/distributed systems** — secure pubkey-addressed p2p overlay, STUN,
  NAT traversal, DERP relay, SWIM membership, state-based CRDTs (PN-Counter,
  LWW-Register, OR-Set), gossip replicator, consistent-hash ring, distributed
  computation (Crown).

### Targets & tooling

- Native: Linux x86_64, Windows x86_64, macOS x86_64/ARM64.
- WebAssembly `wasm32-wasi` (WASI SDK), including the compiler itself running
  in the browser playground.
- Static cross-compiles: Linux ARM64 / RISC-V64 (musl). Milk-V Duo (RISC-V
  C906) validated on-device.
- `nurlfmt` canonical formatter (idempotent, IR-preserving), `nurl-lsp`
  (completion, references, unused-symbol lint), `nurlpkg` package manager,
  DWARF debugging, VS Code extension, and the `nurlapi` compiler-as-a-service
  container (playground + cross-compile endpoints + public MCP server).
- Showcase programs in [`examples/`](examples/) including a Game Boy emulator
  (with sound), a C64 demo, ESP32 / Milk-V embedded targets, and a
  Push-To-Talk distributed voice app (`pttvoice/`).

---

## Toward 1.0

The remaining work to declare a stable 1.0 is mostly precision and proof, not
new language features.

### Documentation precision (safety & soundness)

- [x] **State the safety contract exactly** — which bug classes the borrow
  checker rejects vs. tolerates, with no implied Rust-equivalence
  ([`docs/MEMORY.md`](docs/MEMORY.md), [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md)).
- [x] **Write the soundness story** — decide and document whether
  interprocedural escape analysis and `*T` raw-pointer flows are on the
  roadmap or out of scope by design; the checker is currently incomplete
  there by design. *(Resolved: interprocedural escape and return-escape implemented.)*
- [x] **Document the known auto-drop leaks** (nested owned-struct fields,
  arm-local fall-through bindings, allocations inside a `recover` scope). *(Resolved: leaks fixed.)*

### Evidence for the "LLM-native" thesis

These convert a hypothesis into measured results.

- [x] **Tokenizer-level token-count study** — measured real BPE tokens (not
  characters) for NURL vs Python/Rust/JS across 8 matched programs
  ([`bench/TOKEN_EFFICIENCY.md`](bench/TOKEN_EFFICIENCY.md)). *Result: the
  raw token-count claim did not survive measurement — on today's tokenisers
  NURL is ~1.7× Python's tokens (median), losing to out-of-distribution
  glyph fragmentation. The claim was retired; the defensible arguments are
  grammar regularity and first-pass compile success.*
- [x] **Controlled generation-accuracy comparison** — first-pass compile +
  correctness, NURL vs Python/Rust, across four models (Sonnet 4.6 / Opus
  4.8 / Haiku 4.5 / mercury-2 diffusion), primed with NURL's one-page
  reference since the training corpus contains zero NURL
  ([`bench/genacc/`](bench/genacc/), results in
  [`bench/genacc/RESULTS.md`](bench/genacc/RESULTS.md)). *Result: from a
  single page a model reaches the Python/Rust ballpark on several tasks but
  not parity; failures are out-of-distribution habits (imports, then
  grouping-parens, then mutability) that targeted primer cues fix in turn.*
- [ ] **Separate the language claim from the MCP-integration claim** in
  project copy — "an agent can drive the toolchain over MCP" is a tooling
  win, not evidence the *language* is better for LLMs.

### Project health

- [ ] **Reduce bus factor** — recruit at least one additional reviewer /
  maintainer and publish a short governance note (license stays MIT OR
  Apache-2.0).

---

## Planned (post-1.0 direction)

Not blocking 1.0; ordered roughly by likely value.

- **Mobile & embedded targets** — Android (NDK), iOS, and a `no_std`-style
  embedded profile. The RISC-V / ARM64 static cross-compiles already prove the
  shape; these extend it.
- **Runtime split (organisational)** — separate `stdlib/runtime.c` into
  bootstrap-internal helpers vs. stdlib FFI shims. The PURIFY effort already
  moved most platform code into pure-NURL `& \`c\`` FFI; the file-level split
  itself remains.

---

## Research / exploratory

Ideas under consideration, no committed timeline.

- **Compiler-embedded LLM** — LLM-assisted, self-correcting compile-error
  suggestions, leaning on the regular grammar and local error semantics.
- **Additional backends** — JVM bytecode and .NET CIL are conceivable given
  the simple IR, but are not on the near-term path.

---

## Non-goals

Deliberate exclusions, to set expectations:

- **GC or reference-counting by default.** Single-owner + auto-drop is the
  model; `rc`/`arc` are opt-in library types.
- **`async`/`await` function colouring.** Concurrency is via stackful fibers;
  ordinary code is scheduler-agnostic.
- **Infix operators / operator precedence.** Prefix-arity is the grammar's
  whole point.
- **Implicit numeric conversions / subtyping.** Casts are always explicit
  (`#`).
- **Catching hardware faults** (SIGSEGV/SIGFPE/SIGBUS) via `recover` — only
  explicit `panic` is recoverable; faults remain process aborts.

---

## How to read progress

- **Shipped, with proof** → it has a test in `compiler/tests/` and survives
  the bootstrap fixed point; details in [`CHANGELOG.md`](CHANGELOG.md).
- **Toward 1.0 / Planned** → unchecked boxes here; the working notes that seed
  them live in [`TODO.md`](TODO.md) (a scratch checklist, not authoritative).
- **Language reference** → [`docs/spec.md`](docs/spec.md) (normative) and
  [`spec/grammar.ebnf`](spec/grammar.ebnf) (authoritative grammar).
