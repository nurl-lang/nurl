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

---

## Design Principles

### 1. Regular grammar
NURL's grammar has no exceptions — the same construct always works the same way. The grammar fits on a single page.

### 2. Local semantics
A construct's meaning is derivable from a short window of surrounding tokens. No long-range dependencies.

### 3. Deterministic compiler
The same source always produces identical output. No UB, no platform differences, no behavioral variation. Code behaves as written.

### 4. Full platform support
One compilation pipeline → all target platforms without porting.

### Performance

A reproducible micro-benchmark suite lives in [`bench/`](bench/) — one source file per language, `bench/run.sh` compiles + runs every present language N times, prints a median-ms table. [`bench/RESULTS.md`](bench/RESULTS.md) captures the numbers from one specific machine (12-core Intel @ 3.5 GHz):

| Benchmark         | NURL  | Python  | Rust  | Node    |
|-------------------|------:|--------:|------:|--------:|
| `lcg` (100M LCG iters)         |  10   | 27 459  |  16   |  9 680  |
| `sieve` (π(10M))               |  69   |  5 898  |  62   |    142  |
| `json_parse` (5× 64 KB)        |  14   |     34  |   5   |     47  |

(Lower = better, median wall-clock ms across 5 runs.)

**HTTP server peer bench** — [`bench/HTTP_RESULTS.md`](bench/HTTP_RESULTS.md), driven via [`oha`](https://github.com/hatoo/oha) (10 s × 3 runs, median):

| Concurrency | NURL (req/s) | Rust hyper | Node http | NURL p99 (ms) | Rust p99 | Node p99 |
|---:|---:|---:|---:|---:|---:|---:|
|   1 |  14 451  |  14 507  |   8 708  |  0.14 | 0.11 |  0.51 |
|  10 |  68 960  |  47 703  |  16 726  |  0.56 | 1.16 |  2.43 |
|  50 |  60 897  |  86 699  |  17 108  |  0.67 | 2.82 | 12.30 |
| 200 |  59 044  | 114 694  |  15 555  |  0.62 | 6.19 | 21.16 |

---

## Architecture

```
NURL source (.nu)
        │
        ▼
   Tokenizer
   (deterministic, context-free)
        │
        ▼
     Parser
   (LL(k≤4), ≤4-token lookahead)
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

The compiler (`nurlc.nu`) is written in NURL itself. The bootstrap runs it
twice over its own source and requires byte-identical LLVM IR on both rounds
before the build is accepted.

---

## Editor support

Syntax highlighting **plus a full Language Server** (go-to-definition,
hover, document outline, completion, workspace symbol search, folding,
`nurlfmt`-backed formatting, live compile diagnostics) for VS Code,
Cursor, and Windsurf is available in `tooling/vscode-nurl/`.

**One-command install from a checkout:**

```bash
git clone https://github.com/nurl-lang/nurl.git
cd nurl
./install.sh
```

`install.sh` is idempotent — re-run any time. It bootstraps the
compiler, builds `nurl-lsp`, symlinks it into `~/.local/bin/`,
packages the VS Code extension, and installs it via the editor's
CLI (`code` / `cursor` / `windsurf`, whichever is on PATH). Flags:
`--no-vscode` (skip the extension step), `--no-path` (don't touch
`~/.local/bin`), `--force` (rebuild even when artefacts exist),
`--uninstall` (remove the symlink + extension).

**Manual install from a local checkout:**
1. `./build.sh` then `./tools/nurl-lsp/build.sh`
2. `Ctrl+Shift+P` → "Extensions: Install from VSIX..."
3. Select `tooling/vscode-nurl/nurl-0.4.4.vsix`

The browser-based playground (see below) ships a Monaco port of the same
tokenizer — no install required.

### Canonical formatter

`./build.sh` also produces `build/nurlfmt` — a deterministic, opinionated
source formatter analogous to `gofmt` / `rustfmt`. Specification:
[`docs/FORMAT.md`](docs/FORMAT.md). Common invocations:

```bash
./nurlfmt.sh <file.nu>              # format → stdout
./nurlfmt.sh --write   <file.nu> …  # rewrite in place
./nurlfmt.sh --check   <file.nu> …  # CI gate; exit 1 if non-canonical
cat src.nu | ./nurlfmt.sh           # stdin → stdout
```

Round-trip acceptance — every shipped `.nu` file round-trips byte-for-byte:
`fmt(fmt(x)) == fmt(x)` AND `nurlc(fmt(x)) == nurlc(x)`. Enforced by
`compiler/tests/nurlfmt_idempotent.sh`.

### Package manager

`./tools/nurlpkg/build.sh` produces `build/nurlpkg` — a Cargo-shaped
package manager that covers the full dependency lifecycle for
path-based dependencies (registry-style version resolution is not in
scope for v1). Manifests use a TOML subset compatible with the
`stdlib/ext/toml.nu` parser.

```bash
build/nurlpkg init demo-app                  # write nurl.toml skeleton
cd demo-app
build/nurlpkg add http-router --path ../router --version 0.2.0
build/nurlpkg install                        # symlink deps/, write nurl.lock
build/nurlpkg verify                         # CI gate: exit 1 on lockfile drift
```

Subcommands: `init`, `info`, `deps`, `add`, `remove`, `install`,
`lock`, `verify`, `version`, `help`. Run `nurlpkg help` for usage.

### Language Server (LSP)

`./tools/nurl-lsp/build.sh` produces `build/nurl-lsp` — a stdio
JSON-RPC server with diagnostics, go-to-definition, hover, document
symbols, completion, formatting, workspace symbol search, and
folding ranges. Wired to VS Code / Windsurf via the
`tooling/vscode-nurl` extension.

---

## HTTP API & browser playground

A pure-NURL HTTP server under `nurlapi/` (the API, router, MCP transport
and OpenAPI emitter are all written in NURL — `nurlapi/main.nu` compiled
to a native binary at image-build time, no Python in the runtime image)
exposes the compiler over HTTP and hosts a Monaco-based playground that
builds and runs NURL programs as **WebAssembly (wasm32-wasi)** directly
in the browser via
[`@bjorn3/browser_wasi_shim`](https://github.com/bjorn3/browser_wasi_shim).
The same container also serves the public **MCP endpoint** at `/mcp` — see
the [MCP section below](#mcp-server--let-an-llm-drive-the-toolchain).

### Endpoints

- `GET /`            — playground UI (editor, examples dropdown, build/run/download).
- `GET /health`      — liveness probe; reports whether `nurlc` is available.
- `POST /build_wasm` — compile NURL source to `wasm32-wasi`.
  Body: `{"source":"…","filename":"main.nu","return_format":"json"|"binary","emit_ll":false}`.
  JSON mode returns base64-encoded wasm + compile logs; binary mode returns
  raw `application/wasm` bytes.
- `POST /build`         — compile NURL source to a native Linux **x86_64 ELF**
  (clang + `stdlib/runtime.o`). Returns structured build logs plus one-shot
  download tokens for the generated `.ll` and the binary.
- `POST /build_windows` — cross-compile to a Windows **x86_64 `.exe`** via
  mingw-w64 (`clang --target=x86_64-w64-mingw32` + `x86_64-w64-mingw32-gcc`
  link). Runtime is pre-built with static libcurl (Schannel TLS) so HTTP
  works end-to-end; canvas/audio FFIs are rejected up-front.
- `POST /build_macos`   — cross-compile to a macOS **x86_64 Mach-O** binary
  via `zig cc --target=x86_64-macos-none`. Links only libSystem (no Apple
  SDK or redistributables); the binary is unsigned, so users must clear the
  Gatekeeper quarantine attribute (`xattr -d com.apple.quarantine <bin>`)
  before running. canvas/audio FFIs are rejected; HTTP links against
  runtime stubs that return `HttpErr::Other` (no libcurl on this target).
  Kept as a thin wrapper over `/build_target` for backward compatibility.
- `POST /build_target`  — cross-compile to any registered **zig target**:
  `linux-{x64,arm64,riscv64}-musl` (fully-static ELF), `linux-arm64-gnu`
  (dynamic glibc ELF), `macos-{x64,arm64}` (Mach-O — incl. native Apple
  Silicon). Body adds `"target":"<id>"`. NURL's IR carries no target
  triple, so one `zig cc --target=` drives them all; canvas/audio/HTTP
  are unsupported on these targets, same contract as `/build_macos`.
- `GET /targets`        — list every selectable compile target (the
  playground builds its **Target** dropdown from this).
- `GET /download/{token}` — stream a build artifact registered by one of the
  `/build*` endpoints. Tokens expire automatically.
- `GET /examples`    — list bundled examples (`examples/*.nu`).
- `GET /examples/{name}` — fetch a specific example's source.
- `GET /grammar`     — current grammar rendered as HTML (from `spec/grammar.ebnf`).
- `GET /readme`      — this README rendered as HTML.
- `GET /openapi.json` — OpenAPI 3.1 schema; `GET /docs` — Swagger UI (loads the schema from `/openapi.json`).

### Build & run the container

From the **repository root** (the build context must be the repo root so
the Dockerfile can access `build.sh`, `compiler/`, `stdlib/`, `examples/`,
`spec/`, `README.md`):

```bash
docker build -f nurlapi/Dockerfile -t nurl-api:dev .
docker run --rm -p 8000:8000 nurl-api:dev
# → http://localhost:8000/         (playground)
# → http://localhost:8000/docs     (Swagger UI)
```

### Pipeline inside the container

1. `nurlc <file.nu>` → LLVM IR on stdout.
2. The API rewrites the IR to match the `wasm32-wasi` ABI
   (renames `@main` → `@__main_argc_argv`, injects the target triple,
   inserts i32/i64 shims for `malloc`/`puts` to match libc signatures).
3. `clang --target=wasm32-wasi -O2 <ir>.ll /opt/nurl/stdlib/runtime.wasm.o -o out.wasm`
   using the WASI SDK (24.0) bundled into the image.

The wasm-compiled NURL runtime (`stdlib/runtime.wasm.o`) is baked into the
image at build time. See `nurlapi/README.md` for image details and the
local-dev path (`./nurl.sh nurlapi/main.nu nurlapi/nurlapi && ./nurlapi/nurlapi`
runs the server outside Docker, using the host's `nurlc` and stdlib).

### Compiler-in-wasm (offline / embeddable)

The same `POST /build_wasm` pipeline can be pointed at `compiler/nurlc.nu`
itself, producing a ~316 KB `nurlc.wasm` that **is** the NURL compiler:

```bash
./startdev.sh        # one terminal: bring up the API container
./buildwasm.sh       # → ./nurlc.wasm  (POSTs nurlc.nu to /build_wasm)
./wasmnurl.sh examples/showcase.nu   # uses nurlc.wasm under wasmtime
```

Once built, `nurlc.wasm` runs anywhere a WASI host does — `wasmtime`,
`wasmer`, Node's WASI, or a browser shim like `browser_wasi_shim`. This
makes the compiler embeddable into sandboxed environments (browser
playgrounds, untrusted-input frontends, single-binary distributions)
without shipping a per-OS native build. Bootstrap is closed: `nurlc.wasm`
re-compiling its own source produces byte-identical IR to the native
`nurlc`, so the wasm path is a faithful copy of the compiler — useful as
a lightweight regression check on cross-ABI codegen.

---

## MCP server — let an LLM drive the toolchain

The playground container also exposes the NURL toolchain as a **public,
unauthenticated [Model Context Protocol](https://modelcontextprotocol.io/)
endpoint**, mounted at `/mcp` over Streamable HTTP. Point any
MCP-aware client at it and the model can build, browse, and read NURL
from inside its own loop — no local install required.

**Public endpoint:** <https://play.nurl-lang.org/mcp>
(implementation: [`nurlapi/main.nu`](nurlapi/main.nu) — JSON-RPC handler,
Streamable HTTP framing and the tool/resource catalog are all pure NURL,
backed by `stdlib/ext/mcp.nu` + `stdlib/ext/mcp_http.nu`. The playground
is at <https://play.nurl-lang.org>, project home at <https://nurl-lang.org>.)

### Add to Claude Code / Claude Desktop

One-liner:

```bash
claude mcp add --transport http nurl https://play.nurl-lang.org/mcp
```

Cursor, Windsurf, Zed and other MCP-capable IDEs accept the same URL
through their respective config UI (transport: `http` /
`streamable-http`).

### What's on offer

**Tools** (15) — the model invokes these to act on NURL source:

| Group | Tools |
|---|---|
| Build (compile + return artifact) | `nurl_build_native` (Linux x86_64 ELF), `nurl_build_windows` (Win64 `.exe`, mingw-w64), `nurl_build_macos` (macOS x86_64 Mach-O, zig cc), `nurl_build_target` (cross-compile to RISC-V / ARM64 Linux or ARM64 macOS — `target` id is a schema enum), `nurl_build_wasm` (wasm32-wasi) |
| Browse | `nurl_list_examples`, `nurl_list_stdlib`, `nurl_list_tests` |
| Read | `nurl_read_example`, `nurl_read_stdlib`, `nurl_read_test`, `nurl_read_grammar`, `nurl_read_readme`, `nurl_read_roadmap`, `nurl_read_gotchas` |

**Resources** (7) mirror the read-tools as `nurl://` URIs
(`nurl://grammar`, `nurl://readme`, `nurl://roadmap`,
`nurl://gotchas`, `nurl://stdlib/<path>`, `nurl://example/<name>`,
`nurl://test/<name>`) for clients that prefer resource semantics.

**Prompt** (1) — `nurl_coding_assistant`: a compact grammar +
canonical example primer that grounds smaller models before they
write or review NURL code.

### Self-hosting

The `/mcp` mount comes for free with the playground container:

```bash
docker build -f nurlapi/Dockerfile -t nurl-api:dev .
docker run --rm -p 8000:8000 nurl-api:dev
# → http://localhost:8000/mcp     (your private MCP endpoint)
```

Or run the server binary directly without Docker:

```bash
./nurl.sh nurlapi/main.nu nurlapi/nurlapi
./nurlapi/nurlapi   # listens on 0.0.0.0:8000
```

`nurlapi/main.nu` is a NURL program — no Python or Node runtime is
involved. See `nurlapi/README.md` for environment variables.

### Caveats

- Open and unauthenticated. The hosted instance is a free public
  endpoint. Don't push secrets through it; assume the source is
  logged. For trust-sensitive use, self-host.
- Build endpoints accept arbitrary NURL source and run it through
  `clang` inside the container. Container-level sandboxing is the
  only isolation; downstream binaries are returned, not executed.
- Tool/resource catalog tracks `main`. Breaking changes to a tool
  signature are announced in `CHANGELOG.md`.

---

## Syntax — overview

NURL uses **prefix notation**. The structure is always:

```
OP ARG1 ARG2 ... ARGN
```

### Types (single letter)
```
i  — integer (64-bit, signed)
u  — integer (64-bit, unsigned)
f  — float   (64-bit)
b  — boolean
s  — string  (UTF-8, immutable)
v  — void
*T — pointer to T
```

### Operators
```
:  — binding (variable / struct / enum / const decl)
=  — assignment
@  — function definition / aggregate constructor
→  — return type / arrow
.  — member access / indexing
( ) — function call
?  — ternary conditional  /  ?T — option type
?? — pattern match (exhaustive)
~  — loop / for-each / mutability prefix / bitwise complement
&  — and (logical i1, bitwise i64) / FFI decl prefix
|  — or (logical i1, bitwise i64)  / enum-decl separator / slice-literal separator
!  — logical NOT / Result type prefix (! T E)
\  — try-propagate / closure (lambda)
^  — explicit return
#  — type cast
Z  — sizeof
%  — trait / impl decl
$  — import decl
`  — string literal
```

### Example: add two integers
```
@ add i a i b → i { ^ + a b }
```

### Example: conditional
```
? > x 0
  `positive`
  `non-positive`
```

### Example: loop
```
: i n 0
~ < n 10 {
  = n + n 1
}
```

### Example: struct and member function
```
: Point { i x  i y }

@ dist Point p → f {
  ^ + * . p x . p x
      * . p y . p y
}
```

### Example: function call
```
( add 3 4 )
( dist myPoint )
```

Parens are **mandatory** around every call — `( fn args )` is the only
call form. A bare identifier `fn` is a name lookup, never a call. The
following tokens land in the surrounding expression rather than as
implicit arguments, which is why a missing pair of parens typically
surfaces as an "unexpected token" several tokens later.

### Example: mutability (default immutable)
```
: i x 10            // immutable — reassignment is a compile error
: ~ i counter 0     // mutable — ~ prefix
= counter + counter 1
```

### Example: enum + pattern match
```
: | Json { JNull  JBool b  JNum i  JStr s }

@ describe Json v → s {
  ^ ?? v {
      JNull  → `null`
      JBool x → ? x `true` `false`
      JNum n → ( nurl_str_int n )
      JStr s → s
    }
}
```

### Example: slice literal + for-each
```
: [i nums [ i | 1 2 3 4 5 ]
: i total 0
~ n nums { = total + total n }
```

### Example: closure (lambda)
```
: (@ i i) square \ i x → i { * x x }
( apply square 7 )          // 49
```

### Example: Result type + try-propagate
```
@ parse s src → ! i ParseErr { ... }

@ sum_two s a s b → ! i ParseErr {
  : i x \ ( parse a )       // `\` unwraps Ok, propagates Err
  : i y \ ( parse b )
  ^ @ ! i ParseErr { + x y }
}
```

### Example: trait with default method
```
% Shape [T] {
  @ area T obj → i                 // required
  @ describe T obj → i {           // default body
    ( nurl_print ( nurl_str_int ( area obj ) ) )
    ^ 0
  }
}

% Shape Rect { @ area Rect r → i { ^ * . r w . r h } }
```

---

## Memory model

The current compiler is deliberately minimal:

- **Default-immutable bindings** — `: i x 0` is immutable; opt in to mutation with `: ~ i x 0`. The compiler rejects assignment to immutable bindings at compile time.
- **No garbage collector** — values live on the stack by default; heap allocation goes through the C runtime (`malloc` / `free` via FFI). No GC pauses, no hidden boxing.
- **Slices and strings are fat pointers** — `[T` compiles to `{ T*, i64 }` (pointer + length); the string type `s` is currently a C-style `i8*` pointer, but user code can wrap it in a `{ s ptr, i len }` struct for bounds-safe operations (see `tests/test_11_fat_strings.nu`).
- **Option-style nullability via `?T`** — compiles to `{ i1, T }`, checked with `??` pattern matching.
- **Struct parameters pass by value, like C / Go / Zig** — the compiler emits `alloca + store` for each struct-typed parameter at function entry, so `= . p field val` inside the callee writes to a fresh local backing. NURL has no `&local` address-of operator; the three ways to share mutation across a call boundary are **(a)** return the modified struct (idiomatic — copy is cheap for small structs), **(b)** declare a `*T` parameter and pass the alloca address, or **(c)** wrap the state in a single-handle struct (`{ ( Vec i ) counters }`) so the heap buffer is shared even though the handle is copied. See `stdlib/ext/http_middleware.nu` `Metrics` for the (c) pattern.
- **Single-owner + compiler-inserted auto-drop** — the compiler tracks ownership of heap-allocated slices and strings and emits `nurl_free` at scope exit automatically. Closures still use RC for captured env.
  - Slice-literal ownership: a `[ T | ... ]` literal is owned by the binding it is assigned to and dropped at function exit.
  - Slice-returning function calls transfer ownership to the caller's binding.
  - String auto-drop for allocating runtime calls (`nurl_str_cat`, `_cat3/4`, `_int`, `_float`, `_slice`, `nurl_read_file`). Retaining C runtime helpers (`nurl_lex_new`, `nurl_set_last_type`, `nurl_get_last_type`, `nurl_argv`, `nurl_sym_get`, `nurl_lex_filename`, `nurl_print_buf_stop`) `strdup` their inputs/outputs so callers can auto-drop safely. `?`, `~`, and `??` arms scope their `:` bindings in a new symtab frame so owned-string entries do not leak into sibling branches. Reassigning an owned `i8*` to a fresh allocating call frees the previous value first; allocating-call results passed inline as call arguments are released right after the callee returns (callee-borrows convention — retaining helpers must `strdup`).
  - Struct-field auto-drop: when a named-struct literal `@ T { ... }` populates a field directly from a fresh owned allocation, the compiler records a per-field drop against the binding's alloca and emits a load + `extractvalue` + `nurl_free` at scope exit. Covers `i8*` fields populated from allocating string calls and slice `[T` fields populated from a slice literal or a slice-returning call. Only fields populated from a fresh allocation on the spot get a drop, so copying an already-owned binding into a struct does not cause a double-free. Nested owned-struct fields and arm-local struct bindings that fall through (no `^`) still leak, same as the arm-scoped string behaviour.
- **Static borrow checker, on by default — diagnostics are HARD ERRORS** — a diagnostic analysis pass (disable with `--no-borrowck`) catches the mistakes the conservative auto-drop layer cannot detect: reading a binding after its ownership has moved (use-after-move), aliasing an owned heap value so the buffer would be freed twice, closures that capture a `: ~`-mutable struct by pointer and then escape the stack frame they point into (returned, pushed into a container, spawned onto a thread, or assigned into a longer-lived binding), aliased exclusive-access ("N readers XOR 1 writer") at a call site, and mutating a container while a `~`-foreach borrows its elements. These are **compile errors** — `error: use of moved value …` / `error: cannot mutate 'xs' while iterating over it` — and the compiler exits non-zero with the count of violations. The checker never changes generated code, so a borrow-clean program produces byte-identical IR with or without `--no-borrowck`. Full rules and the not-yet-checked list (`*T`, interprocedural escape): [`docs/MEMORY.md`](docs/MEMORY.md).

---

## Type system

- **Strong, static** — all types known at compile time
- **Inference** — types inferred automatically, annotations optional
- **Algebraic** — sum types (`|`) and product types (structs)
- **No subtyping** — no implicit conversions, no surprise behavior

---

## Target platforms

The compiler emits LLVM IR and delegates native codegen to `clang`, so any
target clang supports is reachable in principle. Only the first two are
exercised by the build scripts today.

| Platform          | Backend      | Status                                   |
|---|---|---|
| Linux x86_64      | LLVM         | primary dev target — `build.sh` + tests  |
| Windows x86_64    | LLVM         | fully supported — `build.bat` runs the same bootstrap + snapshot test suite as `build.sh` |
| macOS x86_64      | LLVM + zig cc | cross-compiled from the `nurlapi/` container via `POST /build_macos`; Mach-O binary links only libSystem (no Apple SDK needed). Runs on Apple Silicon via Rosetta 2. canvas/audio/libcurl-HTTP not supported on this target. |
| macOS ARM64       | LLVM + zig cc | cross-compiled via `POST /build_target` (`target=macos-arm64`) — native Apple Silicon Mach-O, links only libSystem. Unsigned, so clear quarantine attribute before running. |
| WebAssembly       | wasm32-wasi  | supported via the `nurlapi/` container (WASI SDK 24.0); browser execution via `browser_wasi_shim`. The self-hosting compiler itself also builds to wasm — see `buildwasm.sh` / `wasmnurl.sh` below |
| Linux ARM64 / RISC-V64 | LLVM + zig cc | cross-compiled via `POST /build_target` — fully-static `musl` ELFs (`linux-arm64-musl`, `linux-riscv64-musl`) or dynamic glibc (`linux-arm64-gnu`). Milk-V Duo (RISC-V C906) validated on-device. |
| Android / iOS     | LLVM cross   | planned                                  |
| Embedded (no_std) | LLVM         | planned                                  |
| JVM               | JVM bytecode | future                                   |
| .NET CLR          | CIL          | future                                   |

---

## Networking

NURL reaches the network through a pure-POSIX socket layer in the C
runtime (`nurl_tcp_*` / `nurl_udp_*` / `nurl_dns_*`) — no libcurl,
no framework. Four primitives, every one of them dual-stack IPv4/IPv6
and integrated with the fiber reactor for async I/O:

- **TCP server** — `tcp_listen` / `tcp_listen_tls` + `tcp_accept`,
  with a full HTTP/1.1 server stack on top (`stdlib/ext/http_*` —
  routing, static files, middleware, multipart, WebSockets, TLS
  with SNI + ALPN + mTLS + live cert reload).
- **TCP client** — `tcp_connect` / `tcp_connect_tls` (runtime §18).
  TLS client handshake with SNI; peer-certificate verification is
  an opt-in flag. The primitive behind the MQTT 5.0 client and any
  outbound TLS application.
- **UDP** (`stdlib/std/udp.nu`, runtime §18b) — `udp_bind` (dual-
  stack wildcard via `AF_INET6 + IPV6_V6ONLY=0`), `udp_connect`,
  `udp_send_to` / `udp_recv_from`, connected-mode `udp_send` /
  `udp_recv`, broadcast and multicast (`udp_join_group` /
  `_leave_group` / `_set_multicast_ttl` / `_set_multicast_loop`).
  Sync + fiber-aware async on every send/recv via the same context
  dispatch as the TCP primitives.
- **DNS** (`stdlib/std/dns.nu`, runtime §18c) — system-resolver
  wrappers over `getaddrinfo` / `getnameinfo`, no c-ares dep.
  `dns_resolve host → ! (Vec String) NetErr` lists the A/AAAA
  literals in the kernel's preferred order; `dns_resolve_port host
  port` formats each entry as `"ip:port"` (IPv4) or `"[ip]:port"`
  (IPv6, RFC 3986 §3.2.2) ready for direct `tcp_connect` /
  `udp_connect`; `dns_reverse ip → ? String` runs `NI_NAMEREQD`.

### MQTT 5.0 client

`stdlib/ext/mqtt.nu` is a production-grade MQTT 5.0 client built on that
socket layer. The whole packet codec is pure NURL over `( Vec u )` — no
extra dependencies beyond the runtime's libssl.

```
$ `stdlib/ext/mqtt.nu`

@ main → i {
    : !MqttClient MqttErr r ( mqtt_connect
        `broker.example.com` 8883 `client-id` `user` `pass` )
    ?? r {
        T cl → {
            : !v MqttErr s ( mqtt_subscribe cl `sensors/#` )
            ?? s { T → {} F e → {} }
            : !v MqttErr p ( mqtt_publish1 cl `sensors/temp` `21.4` )
            ?? p { T → {} F e → {} }
            ( mqtt_disconnect cl )
            ^ 0
        }
        F e → { ( nurl_eprint ( mqtt_err_name e ) ) ^ 1 }
    }
}
```

What it covers:

- TLS (port 8883) or plain TCP (1883); MQTT 5.0 CONNECT via a
  configurable `MqttConfig` — Last Will, session expiry, clean-start.
- PUBLISH at **QoS 0 / 1 / 2** (the full PUBREC/PUBREL/PUBCOMP
  exchange), the `retain` flag, and MQTT 5 user properties.
- SUBSCRIBE / UNSUBSCRIBE at a chosen max QoS; `mqtt_receive` returns
  inbound messages and auto-acknowledges QoS 1/2.
- A **framed packet reader** — a packet split across TCP segments, or
  several packets in one segment, is reassembled correctly.
- Keep-alive (`mqtt_ping` / deadline-aware `mqtt_keepalive_tick`), a
  rotating packet-id allocator, `mqtt_reconnect`, and `mqtt_listen` —
  a background reader thread that feeds inbound messages through a
  channel while the application does other work.
- Typed errors (`MqttErr`): transport faults are distinct from broker
  rejections (`MqttBadAuth`, `MqttNotAuthorized`, …).

`example/mqtt_*.nu` are runnable demos verified against a live broker.

---

## Project structure

```
nurl/
├── spec/                      — formal language specification
│   ├── grammar.ebnf           ✓ current grammar
│   ├── types.md
│   ├── ir.md
│   └── bootstrapping.md
├── compiler/
│   ├── nurlc.nu               ✓ self-hosting compiler, written in NURL
│   ├── nurlc_lastgood.nu      — committed bootstrap snapshot (NURL source)
│   ├── nurlc_lastgood.ll      — committed bootstrap snapshot (LLVM IR; clang links to a boot binary)
│   └── tests/                 — `.nu` test programs + snapshot runner
│       ├── run_tests.sh       — Linux/macOS test runner
│       ├── run_tests.bat      — Windows test runner
│       ├── correct.txt        — golden baseline (status + output per test)
│       └── *.nu               — positive and negative tests
├── stdlib/
│   ├── runtime.c              ✓ C runtime (I/O, string helpers, FFI surface)
│   ├── runtime.o              — native host build
│   └── runtime.wasm.o         — wasm32-wasi build (produced inside the API image)
├── examples/                  — curated `.nu` programs surfaced by the playground
│   ├── showcase.nu  calculator.nu  fizzbuzz.nu  collatz.nu  wordcount.nu
│   └── enigma.nu  slice_test.nu  test_05_closures_and_capture.nu …
├── nurlapi/                   — NURL-native container (compiler-as-a-service + playground + MCP)
│   ├── Dockerfile             — multi-stage build; installs WASI SDK + zig + mingw; bootstraps nurlc; compiles `main.nu` to a native binary
│   ├── main.nu                — endpoints, router, IR-rewrite shims, OpenAPI emitter, MCP handler — all NURL
│   ├── static/index.html      — Monaco-based playground, runs wasm in-browser
│   └── e2e_test.{py,sh}       — end-to-end suite hitting the running container
├── tooling/
│   └── vscode-nurl/           — VS Code / Windsurf syntax-highlighting extension
├── build/                     — all bootstrap artefacts land here
│   ├── nurlc_lastgood.bin     — stage 0: clang-linked from `compiler/nurlc_lastgood.ll`
│   ├── nurlc_self(.ll)        — stage 1: self-compiled
│   ├── nurlc_self2(.ll)       — stage 2: fixed-point check
│   └── nurlc                  — final self-hosting binary
├── build.sh / build.bat       — full bootstrap + test-suite driver
├── clean.sh / clean.bat       — remove build artefacts
├── nurl.sh  / nurl.bat        — convenience wrapper to compile a `.nu` file
└── nurlc                      — symlink to build/nurlc (Linux/macOS)
```

---

## Building

### Prerequisites

| Tool | Purpose |
|---|---|
| clang / LLVM 14+ | Compile LLVM IR (`.ll`) to native binary; only build-time dependency |

No Python, no make, no language-specific package manager. Clone the
repo and run `./build.sh` (or `build.bat` on Windows). The
committed `compiler/nurlc_lastgood.ll` snapshot is the only thing
that boots the self-hosted chain.

#### Windows

Install LLVM from [llvm.org/releases](https://llvm.org/releases/) (choose the Windows installer for the latest stable release).
The installer adds `clang.exe` and related tools to `PATH`.

You can use Command Prompt, PowerShell, or Git Bash for the commands below.

#### Linux (Debian / Ubuntu)

```sh
sudo apt install clang
```

#### Linux (Fedora / RHEL)

```sh
sudo dnf install clang
```

#### macOS

```sh
brew install llvm
# Add LLVM to PATH for this shell (add to ~/.zshrc or ~/.bash_profile to persist):
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

---

### Step 1 — Build the C runtime (once)

```sh
# Linux / macOS
clang -c stdlib/runtime.c -o stdlib/runtime.o

# Windows (CMD / PowerShell)
clang -c stdlib\runtime.c -o stdlib\runtime.o
```

> `stdlib/runtime.o` is already checked in; rebuild it only if you modify `runtime.c`.

---

### Step 2 — Bootstrap the self-hosting compiler

Use the automated build scripts to bootstrap the compiler and verify stability:

```sh
# Linux / macOS
./build.sh

# Windows (CMD / PowerShell)
build.bat
```

The build script performs a complete bootstrap process:
1. Links the committed `compiler/nurlc_lastgood.ll` snapshot →
   `build/nurlc_lastgood.bin` (stage 0; the only step that doesn't
   already need a working `nurlc`)
2. `nurlc_lastgood.bin` compiles `compiler/nurlc.nu` → `build/nurlc_self` (stage 1)
3. `nurlc_self` compiles `compiler/nurlc.nu` again → `build/nurlc_self2` (stage 2)
4. Verifies stages 1 and 2 produce byte-identical LLVM IR (bootstrap fixed point)
5. Copies stage 2 to `build/nurlc` and symlinks it at the repo root
6. Runs the snapshot test suite (`compiler/tests/run_tests.sh` on Linux/macOS, `compiler/tests/run_tests.bat` on Windows) and diffs against `correct.txt`

When a grammar / runtime-ABI change leaves the committed snapshot
unable to compile current `nurlc.nu`, refresh it with
`./build.sh --refresh-bootstrap` (uses the EXISTING `build/nurlc` to
regenerate both `compiler/nurlc_lastgood.nu` and `.ll`; commit both
files together).

All build artefacts are stored under `build/`. The run prints
`BUILD SUCCESS & TESTS PASSED` on success, or the full log / diff on failure.

**Clean build artifacts:**
```sh
# Linux / macOS
./clean.sh

# Windows (CMD / PowerShell)  
clean.bat
```

**Manual build (if needed):**
```sh
# Create build directory
mkdir -p build  # Linux/macOS
mkdir build     # Windows

# Stage 0: link the committed snapshot IR → a working boot compiler.
clang compiler/nurlc_lastgood.ll stdlib/runtime.o -lm -lpthread -o build/nurlc_lastgood.bin

# Stage 1: boot compiler self-compiles → fresh self-hosted nurlc.
build/nurlc_lastgood.bin compiler/nurlc.nu > build/nurlc.ll
clang build/nurlc.ll stdlib/runtime.o -lm -lpthread -o build/nurlc      # Linux/macOS
clang build\nurlc.ll stdlib\runtime.o -lm -lpthread -o build\nurlc.exe  # Windows
```

---

### Compile any `.nu` file

**Recommended (automated):**
```sh
# Linux / macOS
./nurl.sh myprogram.nu              # Creates myprogram binary
./nurl.sh myprogram.nu myoutput     # Creates myoutput binary  

# Windows
nurl.bat myprogram.nu               # Creates myprogram.exe
nurl.bat myprogram.nu myoutput      # Creates myoutput.exe  
```

**Manual (two-step):**
```sh
# Linux / macOS
./nurlc myprogram.nu > myprogram.ll          # or build/nurlc
clang myprogram.ll stdlib/runtime.o -o myprogram
./myprogram

# Windows
nurlc.exe myprogram.nu > myprogram.ll        # or build\nurlc.exe
clang myprogram.ll stdlib\runtime.o -o myprogram.exe
myprogram.exe
```

---

### Debugging with `gdb` / `lldb` (DWARF)

NURL ships DWARF debug-info support so a NURL binary can be driven by
`gdb` / `lldb` like any other C-toolchain ELF: source-level break-
points, single-step by `.nu` line, `info locals`, `print x` with the
correct NURL-flavoured type name (`i`, `b`, `f`, …).

```sh
./nurl.sh --debug examples/fizzbuzz.nu          # builds fizzbuzz with DWARF
gdb -ex 'break fizzbuzz' -ex run ./fizzbuzz     # break by name
gdb -ex 'break examples/fizzbuzz.nu:18' …       # break by source line
```

Two knobs cooperate:
- `nurlc --g <file>` emits `!DICompileUnit` / `!DISubprogram` /
  `!DILocation` / `!DILocalVariable` metadata into the LLVM IR.
- `nurl.sh --debug` forwards `--g` to nurlc AND links with `-g
  -rdynamic` on a freshly-built non-LTO `runtime_debug.o`. (LTO
  silently drops DWARF in the current LLVM/gcc-ld pipeline, hence
  the side-by-side runtime build.)

Runtime panics print a stack backtrace before aborting; pipe each
frame's `binary+0xOFFSET` through `addr2line -e <binary>` to recover
`.nu:LINE` source locations. ASan / UBSan reports under
`./build.sh --san` already render `.nu` source locations directly.

End-to-end regression test: `./tools/dwarf_test.sh` (no-op when
`gdb` isn't installed).

---

### Bootstrap chain

Stage 0 links the committed `compiler/nurlc_lastgood.ll` snapshot —
pre-compiled IR of `compiler/nurlc_lastgood.nu` (a checked-in mirror of
the last self-host-stable `nurlc.nu`). Anyone with `clang` can clone and
build; no other-language toolchain is required.

  - `compiler/nurlc_lastgood.nu` — NURL source of the snapshot
    (human-readable; identical to `nurlc.nu` at the point it was
    captured).
  - `compiler/nurlc_lastgood.ll` — LLVM IR text (~1.5 MB),
    diffable in git, target-triple-agnostic so the same blob
    bootstraps Linux / macOS / Windows.

Snapshot refresh: `./build.sh --refresh-bootstrap` (re-runs the
EXISTING `build/nurlc` on the current `nurlc.nu` and overwrites
both `.nu` and `.ll`; commit them together).

---

## Known Limitations

Limitations of the current compiler (`nurlc.nu`, grammar v2.1).

For active compiler quirks (binary `&` / `|` arity, bare `@-fn` closure
coercion, same-line parameter shadowing, ternary cascading, `: ~`
closure-borrow escape) see [`docs/GOTCHAS.md`](docs/GOTCHAS.md).

### Type system

| Limitation | Workaround |
|---|---|
| Single-letter type keywords (`i u f b s v`) cannot be used as variable names with type inference | Use an explicit type annotation: `: i n expr` |

### Functions and calls

| Limitation | Workaround |
|---|---|
| Calls require explicit parens — `( f a b )` is the only call form; a bare identifier is always a name lookup, never a call | Wrap every callsite: `( puts s )` |
| Struct parameters are passed by **value** by default (C/Go/Zig semantics) — `= . p field val` inside the callee writes a local copy; the caller's struct is unchanged | Mark the parameter `inout` (`@ bump inout Counter c → v`) — an exclusive mutable borrow, the callee mutates the caller's binding in place (see [`docs/MEMORY.md`](docs/MEMORY.md)). Or return the modified struct (`= c ( inc_returning c )`); or use a `*T` parameter; or wrap state in a single-handle struct (`{ ( Vec i ) slots }`) |
| No tail-call optimisation — deep recursion may stack-overflow | Use explicit loops (`~`) |
| Closures capture by value (snapshot at construction) by default. The `: ~` mutable-struct byref capture path (`stdlib/std/panic.nu` recover-with-typed-result) shares the caller's alloca — see [`docs/GOTCHAS.md` §5](docs/GOTCHAS.md) for the lifetime rule | Use `: ~ MultiFieldStruct` for shared-mutation closures; for value semantics keep the binding immutable |

### Enums

| Limitation | Workaround |
|---|---|
| Enum variants with a named-struct payload require the struct to be declared **before** the enum in the same file — forward references are not supported | Order declarations: structs first, enums after |
| Pattern matching binds at most 3 payload variables per arm — variants with 4+ payloads cannot fully destructure in a single arm | Access additional payload fields via separate `.` extraction after matching |

### Imports

| Limitation | Workaround |
|---|---|
| `import_decl` is a static inline-include (like `#include`) — the imported file is compiled into the same LLVM module | Avoid importing files that define `main`; avoid circular imports |
| Import alias (`` $ `path` alias ``) rewrites top-level `@`-functions, struct/enum types, enum variants, and global `:` constants to `alias__name`. FFI decls (`& "lib" @ name`) and trait/impl methods are intentionally NOT renamed — FFI symbols resolve at the linker by literal C-ABI name, and trait methods are mangled by the impl-target type | Use `pub` to scope FFI declarations to the importing file if collision is a risk |
| `pub` visibility covers `@`-functions, struct/enum types, enum variants (inheriting their enum's flag), and global `:` constants. Files with no `pub` decl stay in legacy mode (everything public, backwards-compat). FFI and trait/impl decls accept `pub` forward-compat but do not enforce — FFI symbols are linker-level ABI globals; trait dispatch is type-mangled | Mark each cross-file API entry with `pub`; the diagnostic `private X 'Y' is not visible across files` points at the leaked-private use site |
| `$`-import dedup is keyed on the path string with a small normalisation (leading `./` is stripped). Symlink-equivalent paths still collide as separate imports | Stick to the project-root-relative form (`stdlib/foo.nu`, no `./` prefix). Use `realpath`-true canonicalisation is on the roadmap if a real case needs it |

### Grammar

| Limitation | Workaround |
|---|---|
| Import is inline-include only: no namespaces. Alias rewriting (`` $ `path` alias ``) now covers `@`-functions, struct/enum types, enum variants, and global `:` constants; FFI decls and trait/impl methods are deliberately not renamed — FFI symbols resolve at the linker by C-ABI name, and trait methods are mangled by impl-target type. Path-string dedup with leading `./` normalisation; same file imported twice (or through a diamond) emits one set of decls | Stick to a single canonical import path per file; prefix FFI names manually when collisions matter |
| **Every operator has fixed arity** (prefix notation has no closing token). `&` / `|` / `^^` / `+` / `-` / `*` / `/` / `==` / `!=` / `<` / `>` / `<=` / `>=` / `<<` / `>>` are all **binary** (`OP A B`). `?` ternary is `? cond then else`, `^` / `!` / `~` are unary. The parser counts operands left-to-right, so a missing or extra operand silently consumes the next token that was meant to start a new statement and the diagnostic ends up on the wrong line | Count operands left-to-right on the previous line when "unexpected token" fires on a line that looks fine. For n-ary `&`/`|` chains write `& A & B C` or `& & & A B C D` (n−1 operators for n atoms) — the compiler warns on the most common shape (`? & A B C D { … } { … }`) since v0.7.1 |
| **`^` is the `return` keyword, not XOR** — but `^^` (two adjacent carets) **is** the native XOR operator. `^ a b` parses as `return (a b …)`; `^^ a b` is exclusive-or (bitwise on integers, logical on `b`). | Use `^^` for XOR: `^^ a b`. The lexer pairs `^^` only when the carets are adjacent, so a stray space (`^ ^`) still means two returns |

### PostgreSQL

| Capability | Notes |
|---|---|
| **PostgreSQL via libpq** in `stdlib/ext/postgres.nu` (`pg_connect` / `_exec` / `_exec_params` / `_get_value` / `_clear` / `_close`) | Pure-NURL FFI — no `runtime.c` changes. Build-time dep: `libpq-dev` (pkg-config). When absent, the compile-time FFI lib-check fires with a clear "install libpq-dev" diagnostic, not a cryptic linker error. |
| Text format only (no binary protocol in v1) | `pg_exec_params` always passes text-formatted params + returns text rows. |
| `Connection` and `PgResult` value handles | Caller must `pg_close` each Connection and `pg_clear` each PgResult — even on Err arms. |
| No async / no LISTEN/NOTIFY / no COPY streaming in v1 | Synchronous query model only. |

### SQLite

| Capability | Notes |
|---|---|
| **In-process SQLite via `stdlib/ext/sqlite.nu`** (`sqlite_open` / `_exec` / `_prepare` / `_bind_*` / `_step` / `_column_*` / `_finalize`) | Build-time dep: `libsqlite3-dev` (pkg-config). When absent, every call returns `SqliteUnsupported`. |
| `:memory:` and file-based databases | No network connection (use `http_post` for remote DBs). |
| `int64` and `text` binds + columns | `BLOB` and `double` deferred — stringify or hex-encode for v1. |
| Transactions are pure SQL (`BEGIN` / `COMMIT` via `sqlite_exec`) | No dedicated transaction helper. |
| Statement lifecycle is caller-managed | `sqlite_prepare` → `sqlite_bind_*` → `sqlite_step` (loop) → `sqlite_finalize`. Reuse a Statement across bind sets with `sqlite_reset`. |

### Panic / recover

| Capability | Notes |
|---|---|
| **`panic s msg → v`** (`stdlib/std/panic.nu`) | Halts execution. If a `recover` frame is active on this thread, longjmps to it; otherwise prints to stderr and aborts. Setjmp/longjmp-based — does NOT run destructors during unwind. |
| **`recover ( @ v ) closure → ! v PanicInfo`** | Run closure under a recover guard. Returns Ok(0) on normal completion, Err(PanicInfo) if the closure called `panic`. Use a `: ~`-mutable multi-field struct + byref-capture for typed returns. |
| Owned heap allocations made inside a recover scope **leak** if their auto-drop didn't fire | Recover is for crash mitigation, NOT routine error handling. Always prefer `! T E` + `\` for expected errors. |
| SIGSEGV / SIGFPE / SIGBUS / SIGABRT are NOT caught | Signal faults remain process-aborts. Async-signal-safety constraints make signal-bridging infeasible without making every runtime function async-signal-safe. |
| HTTP server `handler` invocations are auto-recovered | A handler that panics → worker logs the message to stderr + returns 500 to the client + keeps serving. Worker thread stays alive. |

### HTTPS / TLS

| Capability | Notes |
|---|---|
| **TLS server-side** via `tcp_listen_tls host port cert_path key_path → !TcpListener NetErr` | Build-time dependency: `libssl` (pkg-config). HttpServer integrates without code changes — just swap `tcp_listen` for `tcp_listen_tls`. |
| **TLS client-side** via `tcp_connect_tls host port verify` (runtime §18) | TLS client handshake with SNI; peer-certificate verification is an opt-in flag. The primitive behind the MQTT client and any outbound TLS. |
| TLS 1.2 minimum | TLS 1.0 / 1.1 / SSL 3.0 disabled in the SSL_CTX. |
| **SNI** (RFC 6066 §3) — `tcp_tls_add_sni listener hostname cert key` | Multi-tenant HTTPS — register per-hostname cert/key pairs on one listener; handshake-time selection from client's SNI extension; no-match falls through to the default cert. Idempotent on re-add. |
| **ALPN** (RFC 7301) — `tcp_listen_tls_with_alpn` (server-preference list `"h2 http/1.1"`); `tcp_alpn_protocol conn` reads the negotiated protocol post-accept | Required by HTTP/2-over-TLS (RFC 9113 §3.3). |
| **Mutual TLS (mTLS)** — `tcp_tls_require_client_cert listener ca_bundle strict?`; `tcp_peer_cert_subject conn` reads the peer's DN | Both strict mode (handshake fails without a cert) and opportunistic mode (handshake completes; app decides via the subject string). |
| **Live cert reload** — `tcp_tls_reload listener hostname cert key` | Hot-swaps the SSL_CTX under a per-listener mutex; in-flight `SSL_read` / `SSL_write` on the old ctx survive until close via OpenSSL's refcount. Standard use case: Let's Encrypt rotation triggered from a control endpoint or SIGHUP handler. |

---

## LLM integration

NURL is designed so that:

1. **Generation is reliable** — grammar regularity reduces hallucinations
2. **Errors are local** — a bug in one expression does not propagate
3. **Context window is sufficient** — a complete program fits in an LLM's context
4. **Diffing is easy** — changes are small and localized
5. **Round-trips work** — code → explanation → code preserves semantics

The concrete delivery vehicle for (1)–(5) is the public **MCP server**
at <https://play.nurl-lang.org/mcp> — Claude / Cursor / Windsurf / Zed
can compile, browse and read NURL through it without any local toolchain.
See [MCP server — let an LLM drive the toolchain](#mcp-server--let-an-llm-drive-the-toolchain).

---

## Name

**NURL** = **N**eural **U**nified **R**epresentation **L**anguage

Also:
**NURL** = **N**on-h**U**man **R**eadable **L**anguage

File extension: `.nu`

---

## License

Copyright (c) 2026 The NURL Project Developers.

NURL is dual-licensed under either of:

- [MIT License](LICENSE-MIT) ([LICENSE-MIT](LICENSE-MIT))
- [Apache License, Version 2.0](LICENSE-APACHE) ([LICENSE-APACHE](LICENSE-APACHE))

at your option. SPDX identifier: `MIT OR Apache-2.0`.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in the work by you, as defined in the Apache-2.0
license, shall be dual-licensed as above, without any additional terms or
conditions.
