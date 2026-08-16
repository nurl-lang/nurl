# NURL Roadmap

This roadmap describes where NURL is **today** and where it is going. It is
forward-looking and deliberately concise — the full, reverse-chronological
record of *what shipped when* lives in [`CHANGELOG.md`](CHANGELOG.md).
Anything marked done here has a regression test in
[`compiler/tests/`](compiler/tests/) and is covered by the bootstrap fixed
point.

_Last reviewed: 2026-08-16 · Current release: **0.44.2** · Language: **Grammar
v2.5** ([`spec/grammar.ebnf`](spec/grammar.ebnf))._

---

## Status at a glance

NURL is a small systems language with a regular prefix-arity grammar, a
self-hosted compiler written in NURL, and an LLVM backend. The compiler
bootstraps to a **byte-identical fixed point** on its own source (stage1 ≡
stage2). The only build dependency is clang / LLVM 15+.

What is solid today:

- **Language (Grammar v2.5).** Sum types (`|`) and product types (structs),
  generics over structs and functions (incl. generics over option/result
  types), pattern matching with **match guards**, **or-patterns**, and
  **N-ary payloads**, **trait bounds** on type parameters (`[A: Ord]`), **compile-time constant
  folding** (`const_eval_int`), a full numeric type set (`i` = i64 and
  `u` = byte/u8, plus sized `i8`/`i16`/`i32`, `u16`/`u32`/`u64`, `f` = f64
  and `f32`), tail-call optimization, and
  **variadic FFI** (the `printf` family callable directly). Since 0.40.0 the
  language also spells the two shapes a fast numeric kernel is written in:
  **`v128`**, a first-class by-value SIMD vector type over ~27
  `nurl_v128_*` primitives (§4.1b) that lowers to SSE2 / NEON / wasm
  `simd128` with no CPUID probe and no fallback path, and **wide
  arithmetic** — `nurl_umulhi` (the high half of a 64×64 multiply) plus
  `nurl_addc` / `nurl_subb` / `nurl_mac` for carry chains the backend
  recognises. The grammar decision
  for prefix-arity (no grouping delimiter) is formally locked, and since
  0.37.0 the n-ary `&`/`|` arity trap it makes possible is a **hard error
  by default** (`--no-strict-arity` demotes it to a warning) — the shape
  compiled to working, wrong code before.
- **Memory & safety.** Single-owner memory with compiler-inserted auto-drop at
  scope exit — no GC, no hidden boxing. A **static borrow checker, on
  by default** (`--no-borrowck` to disable, `--strict-borrowck` to tighten),
  catches use-after-move, alias double-free, escaping closure captures,
  interprocedural/return escape, loop-carried double-frees, and
  iterator invalidation as hard errors without changing generated code.
  Since 0.44.0 **no rule depends on definition order**: every check that
  consults a per-function summary parks what it cannot answer and
  resolves it after the module, so where a helper is written can no
  longer change a verdict.
- **Concurrency.** A stackful M:N work-stealing async runtime with **no
  `async`/`await` colouring** — ordinary code runs unchanged under the
  scheduler — plus threads/mutex/cond, typed channels, and Go-style `??`
  channel **select**. Since 0.43.0, **`Send` / `Sync`** marker traits
  ([`stdlib/core/marker.nu`](stdlib/core/marker.nu)) are *derived* over a
  type's whole graph and checked wherever a value crosses a thread
  boundary — `thread_spawn`, `spawn`, `chan_send`, and an `Arc`'s payload
  — so an `Rc` or a `Cell` reaching a worker is a compile error however
  it is spelled, and `% NotSend` / `% Send` mark the cases a structural
  derivation cannot see either way. It is a sound lint, not a proof:
  [`docs/MEMORY.md`](docs/MEMORY.md) §6.5 states what it does and does
  not guarantee.
- **Standard library.** A broad pure-NURL stdlib (see the inventory below)
  spanning collections, hashing, serialization, a full HTTP/1.1+2 + WebSocket
  stack, database clients, distributed systems (p2p overlay, CRDTs), MCP, and the Anthropic Claude API.
- **Targets.** Linux x86_64 (primary, CI-tested), Windows x86_64 (CI-tested:
  bootstrap fixed point + the Windows golden corpus on every push and PR),
  macOS ARM64 (CI-tested on Apple Silicon: bootstrap fixed point + the
  full corpus against the same goldens as Linux, on every push and PR;
  needs Homebrew LLVM, no prebuilt toolchain) and macOS x86_64
  (cross-compiled Mach-O, no CI), `wasm32-wasi`, static Linux ARM64 / RISC-V64
  (musl), and **bootable unikernel images** — a NURL program as its own
  kernel on x86_64, AArch64 and RISC-V64, no host OS and no libc.
  Tier definitions: [`docs/PLATFORMS.md`](docs/PLATFORMS.md).
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
- Grammar evolved v0.1 → **v2.4** (snapshots in [`spec/`](spec/)). v2.x added:
  visibility (`pub`) enforcement across functions, types, consts, and enum
  variants; trait bounds; match guards + or-patterns; const folding; channel
  select; **dynamic trait objects** (`%Trait` + `( dyn Trait v )`, v2.3);
  **`break` / `continue`** as reserved identifiers (v2.4); and locked the
  prefix-arity grouping decision.
- Type system: strong, static, inferred, algebraic; no subtyping, no implicit
  conversions. Sized integer/float types with **signedness carried in the
  type representation itself** (`u`/`u16`/`u32`/`u64` distinct from the
  signed types end to end — no flag side-channels); explicit `#` casts with
  correct `sext`/`zext`/`trunc`/`fpext`/`fptrunc`.
- Generics: monomorphised generic structs and functions (signedness-aware
  monomorphs, including behind `*`/`?` prefixes), generic nesting
  (`Channel[A]`, `Vec[Thread]`), and generics over `?T` / `!T E`.
- Memory model: auto-drop, recursive `Drop` for boxed enum/struct payloads,
  `% Drop` user destructors, move/borrow analysis (incl. interprocedural and
  loop-carried escape detection). Model and known gaps:
  [`docs/MEMORY.md`](docs/MEMORY.md).
- Front-end is diagnostic-first: malformed prefix-arity programs, undefined
  identifiers, call-arity mismatches, unbalanced braces / stray top-level
  tokens, and visibility violations are hard errors with source locations —
  nothing malformed reaches the backend silently. Since 0.39.0 that claim
  is measured corpus-wide: a mutation probe (one realistic mistake injected
  into each of the ~790 test programs, ~5 400 mutants) produces **zero**
  compiler hangs, zero crashes, and zero broken programs reaching the LLVM
  verifier or linker; every return path is type-checked (implicit fall-off
  and closure tails included), and errors inside generic/trait re-parses
  point at the template's real file:line with the instantiation named.
- Diagnostics are *measured*, not asserted. `check_diag_coverage.sh` reports
  which of the compiler's ~230 messages a test has ever made it print;
  `check_diag_anchor.sh` gates that every baselined diagnostic points at the
  mistake rather than at the token after it; `diag_mutate.py` injects one
  realistic error into a working program and reads the answer. Between them
  they have found messages that were false, messages that were unreachable,
  and programs the compiler accepted and miscompiled.
- Emission: only the functions `main` can reach the `.ll`
  (`--no-dce` to emit everything). Reachability is computed over the
  finished IR, so closures, monomorphs, drop glue and dyn vtable thunks
  need no special casing — worth 30–40% of the clang step on a
  stdlib-heavy program. What survives is then emitted as several
  independent modules (`--split=N`) that the driver lowers concurrently
  and links with ThinLTO, taking the clang step on the compiler's own
  3.2 MB of IR from 11.3 s to 2.0 s — at a measured 3.4% of the built
  program's own speed, which is why `nurl.sh` splits your program and
  `build.sh` does not split the compiler it installs (`NURL_SPLIT=0`
  opts out). Since 0.40.0 that link is also **cached** — per-module
  ThinLTO backend codegen, the pre-link object keyed by content hash of
  the emitted IR, and the driver's toolchain probes, all under
  `~/.cache/nurl` — so an empty program links in 99 ms instead of 305
  and a warm rebuild costs less than the equivalent C compile
  (`NURL_CACHE=0` opts out; `NURL_LTO=full` is still the
  maximal-inlining release build). Both passes:
  [`docs/BUILDING.md`](docs/BUILDING.md).
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
  HTTP client (with cookie jar), **TLS** (SNI + ALPN + mTLS + live cert reload; the pure ChaCha20-Poly1305 record path serves past gigabit wire speed, and since 0.40.0 the pure-NURL handshake — X25519 + P-256 ECDHE, ECDSA sign/verify, no assembly and no OpenSSL — runs at 4 894 handshakes/s, 2× its 0.39.0 rate), **HTTP/2**
  (RFC 9113 + HPACK, **server and client**), **WebSocket** (RFC 6455, **server
  and client**, with **permessage-deflate** compression — RFC 7692),
  reverse proxy with binary-safe streaming. The stack has had a
  dedicated security-hardening pass (path-traversal, SSRF, request-smuggling,
  HTTP/2 CONTINUATION-flood + stream-accounting, and clean cross-thread
  listener shutdown) with regression tests, and its serve path is
  peer-benchmarked against Rust hyper and Node
  ([`bench/HTTP_RESULTS.md`](bench/HTTP_RESULTS.md): ahead of hyper at
  low concurrency, an HTTP request served in 2 syscalls).
- **ext/data services** — `sqlite` (production-hardened), `mqtt` 5.0 client,
  `smtp` (mail submission). Postgres and Redis clients live in the registry
  packages `psql` and `redis` (pure NURL — no libpq, no hiredis).
- **ext/AI & agents** — `mcp` (+ `client`, `http`, `session`, `stdio`,
  `registry`, and since 0.40.0 `tasks` — the
  `io.modelcontextprotocol/tasks` extension, so a long-running
  `tools/call` returns a pollable task handle instead of holding a
  JSON-RPC response open) and `anthropic` (Claude Messages API incl.
  streaming SSE + tool-use deltas).
- **ext/packaging** — `semver`, `manifest`, `lockfile`, `resolver`,
  `registry_index`, `pkg_fetch`, `pkg_publish` (the `nurlpkg` backend).
- **ext/misc** — `compress` (zlib/zstd/gzip), `zip` (archives), `tar`, `uuid` (v4/v7),
  `credentials`, `env`.
- **dist/distributed systems** — secure pubkey-addressed p2p overlay, STUN,
  NAT traversal, DERP relay, SWIM membership, state-based CRDTs (PN-Counter,
  LWW-Register, OR-Set), gossip replicator, consistent-hash ring, distributed
  computation (Crown).

### Targets & tooling

- Native: Linux x86_64 (CI-tested), Windows x86_64 (CI-tested), macOS
  ARM64 (CI-tested on Apple Silicon; needs Homebrew LLVM, no prebuilt
  toolchain), macOS x86_64 (cross-compiled, not CI-tested).
- WebAssembly `wasm32-wasi` (WASI SDK), including the compiler itself running
  in the browser playground, and **whole neural networks running client-side
  in the browser** — the pure-NURL ONNX runtime compiled to wasm, executing
  on the CPU (precompiled kernels) or on the visitor's **GPU via WebGPU** (the
  CUDA-C kernels translated to WGSL compute shaders; the `gpu` package's third
  backend). Live YOLOE segmentation and tiny-YOLOv2 detection run in a tab
  with no server inference (`packages/yoloe-demo`, the playground objdet
  demo).
- A **WebAssembly runtime written in pure NURL** (`packages/wasmtime`) that
  decodes and executes real `wasm32-wasi` modules (full int/float instruction
  set, linear/bulk memory, tables + `call_indirect`, WASI + `--dir` file ops),
  with no external runtime — and the compiler **self-hosts on wasm**: `nurlc`
  compiled to `wasm32-wasi` recompiles `nurlc.nu` to byte-identical IR, both
  under the reference `wasmtime` and under this pure-NURL runtime.
- Static cross-compiles: Linux ARM64 / RISC-V64 (musl). Milk-V Duo (RISC-V
  C906) validated on-device.
- **Unikernel: a NURL program boots as its own kernel** — no host OS, no
  libc, no interpreter — on three architectures: x86_64 (QEMU microvm,
  and the same PVH image boots under Firecracker and cloud-hypervisor),
  AArch64 and RISC-V64 (QEMU virt; on AArch64 a flat `Image` wrapper
  covers Firecracker/cloud-hypervisor). Since 0.40.0 the x86_64 image
  also carries a Multiboot2 header beside its PVH note and packages into
  a hybrid BIOS+UEFI disk, so it **boots on real PC hardware off a USB
  stick** — with screen output (EGA text or a UEFI framebuffer) where a
  microvm had a serial port, and a PIT-calibrated TSC where no firmware
  states the frequency. Per-arch QEMU gates run the hosted corpus
  against the same goldens (19–20 each, including the SIMD corpus),
  with virtio net/rng drivers, TLS handshakes in the guest, native fiber
  switches on all three ISAs, and CI booting every architecture on every
  commit.
  The playground builds and boots these images (`POST /build_unikernel`
  + target dropdown), and agents do the same over MCP
  (`nurl_build_unikernel`).
- `nurlfmt` canonical formatter (idempotent, IR-preserving), `nurl-lsp`
  (completion, references, unused-symbol lint), `nurlpkg` package manager,
  DWARF debugging, VS Code extension, and the `nurlapi` compiler-as-a-service
  container (playground + cross-compile endpoints + public MCP server).
- Showcase programs: a Game Boy emulator (with sound), a C64 demo and ESP32
  targets in [`examples/`](examples/), Milk-V Duo programs in
  [`duo/`](duo/), and a Push-To-Talk distributed voice app (`pttvoice/`).
- **Language models run locally, in pure NURL** (`nurllama` + `gguf`):
  pull a GGUF model from HuggingFace (resumable, content-addressed store),
  then `run`, `chat`, or `serve` an **ollama-compatible API** that existing
  clients speak unchanged. A hostile-input GGUF parser, a tokenizer read
  from the model's own metadata, and a llama forward pass whose matvec
  kernels **decode quantised blocks inside the matmul** — Q4_0…Q8_0 and the
  K-quants (Q4_K/Q5_K/Q6_K) — so weights never expand to f32 on the device,
  and the same kernel sources run on the CPU backend byte-identically.
  Verified against independent references at every layer: token IDs vs a
  SentencePiece implementation, logits and greedy text vs a numpy forward
  pass, dequantisation bit-identical to an independent decoder. Architectures
  span llama / qwen2 / gemma3 / phi3 and, since 0.21.0, **diffusion** language
  models: LLaDA2.x, a Mixture-of-Experts `llada2` model that converts from its
  Hugging Face checkpoint (`nurllama convert`, streaming a model larger than
  RAM to GGUF at constant memory) and generates by block denoising — parallel
  commits with token editing, not left-to-right — its logits matched to a
  numpy forward and its decoded ids to a reference-faithful loop.
- **Speech recognition, in pure NURL** (`whisper` + `audio` + `safetensor` +
  `tokenizer`): a WAV goes in and text comes out — *word for word what
  Hugging Face transformers produces from the same model*, on whisper-tiny
  and on distil-large-v3, on the GPU or the CPU. Every stage is verified
  against an independent implementation rather than against our own
  understanding of it: the resampler against scipy, the log-mel against HF's
  own feature extractor (r = 1.00000000, on both 80 and 128 bands), the
  400-point FFT against numpy (Bluestein, because 400 is not a power of two
  and padding it computes a *different* transform), the weights bit-exact,
  the vocabulary against HF's tokenizer, the encoder against HF's encoder,
  and the transcription against HF's. Whisper is not the llama shape —
  LayerNorm rather than RMSNorm, error-function GELU rather than tanh, two
  conv1d layers, cross-attention, and the ecosystem's first **non-causal**
  attention.
- **Package ecosystem** on the live registry (`reg.nurl-lang.org`,
  `nurlpkg install`): GPU compute (`gpu` — CUDA driver + NVRTC, a CPU
  fallback backend, a static-kernel backend, and a **WebGPU / WGSL backend**;
  `gpukit`, `tensor`), pure-NURL vision and ML (`image` PNG/JPEG codecs,
  `onnx` runtime, `objdet`, `yoloe`, `iforest`, `anomaly`, and `mlp` — the
  first *trainable* package, a deterministic sklearn-faithful MLP regressor),
  local LLMs (`nurllama`, `gguf`, `tokenizer`, `safetensor`), speech (`whisper`,
  `audio`), distributed compute (`swarm`, `swarm-mcp`), web
  (`template` HTML templating, `http`), database clients (`psql`, `redis`
  — pure NURL), and application scaffolding (`cli`, `cas`, `wasmbuilder`,
  `nurl-mcp`).
  Installed tools carry runtime data via the manifest's `[install] assets`
  mechanism (staged into `<prefix>/share/<name>/`).
- **The registry itself is a NURL program** (`packages/registry`): a
  self-hostable server speaking the exact `nurlpkg` wire protocol —
  bearer-authenticated publish with server-side checksums, name ownership
  and version immutability, yank/revoke, search, and a server-rendered
  catalog that renders each package's README straight from its published
  tarball. SQLite as the single source of truth; built on the `http`,
  `template` and `md2html` packages and proven end-to-end against the real
  client. (The public reg.nurl-lang.org cutover from the Cloudflare Worker
  is pending deployment.)
- **Signed packages, verified in pure NURL.** The registry signs every
  published tarball with a project Ed25519 key; `nurlpkg` pins the public key
  and verifies the detached minisign signature — using a pure-NURL BLAKE2b +
  minisign implementation (`std/hash_blake2b`, `std/minisign`) — before
  unpacking, **mandatory and fail-closed**. Release archives are signed too;
  the installers always verify the checksum fail-closed and verify the
  minisign signature against a pinned key when `minisign` is available.
  Since 0.41.0 the packer also excludes compiler output by extension, so a
  given revision packs to the same bytes from any clean checkout — a
  checksum identifies the source, not the machine that happened to build it.

---

## Toward 1.0

The remaining work to declare a stable 1.0 is mostly precision and proof, not
new language features.

### Brand: Logo, Images

- Switch from generated imagery to a human-designed one.

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
  not parity first-try; failures are out-of-distribution habits (imports,
  then grouping-parens, then mutability) that targeted primer cues fix in
  turn. The follow-up measured the agentic half of the claim: with ONE
  round of compiler-diagnostic feedback (`bench/genacc/repair.py` — the
  model sees only its program and the compiler's stderr, never the
  expected output), Sonnet and Opus reach **exact Python/Rust parity —
  100% compile, 100% correct** — Haiku reaches 100% compile, and the
  diffusion model quadruples its score. The diagnostic-first compiler is
  the load-bearing artifact, and its value is now measured, not asserted.*
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
- ~~**Runtime split (organisational)**~~ — *done.* `stdlib/runtime.c` is
  split into `stdlib/runtime_core.c` (bootstrap core) and
  `stdlib/runtime_ffi.c` (stdlib FFI shims), stitched by a thin aggregator
  so the single `runtime.o` build is unchanged. The core compiles
  standalone and defines the symbol set the `no_std` profile links.

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
- **Toward 1.0 / Planned** → unchecked boxes here.
- **Language reference** → [`docs/spec.md`](docs/spec.md) (normative) and
  [`spec/grammar.ebnf`](spec/grammar.ebnf) (authoritative grammar).
