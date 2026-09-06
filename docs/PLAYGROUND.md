# HTTP API, browser playground & MCP server

A pure-NURL HTTP server under [`nurlapi/`](../nurlapi/) — the API, router,
MCP transport and OpenAPI emitter are all written in NURL (`nurlapi/main.nu`
compiled to a native binary at image-build time, no Python in the runtime
image) — exposes the compiler over HTTP, hosts a Monaco-based playground
that builds and runs NURL programs as **WebAssembly (wasm32-wasi)** directly
in the browser via
[`@bjorn3/browser_wasi_shim`](https://github.com/bjorn3/browser_wasi_shim),
and serves a public **MCP endpoint** at `/mcp`.

- **Project site:** <https://nurl-lang.org>
- **Playground:** <https://play.nurl-lang.org>
- **MCP endpoint:** <https://play.nurl-lang.org/mcp>

## Endpoints

- `GET /` — playground UI (editor, examples dropdown, build/run/download).
- `GET /health` — liveness probe; reports whether `nurlc` is available.
- `POST /build_wasm` — compile NURL source to `wasm32-wasi`. Body:
  `{"source":"…","filename":"main.nu","emit_ll":false,"opt":"-O2"}` (an
  optional `"ir"` field supplies pre-resolved LLVM IR for multi-file
  packages). Response is JSON: base64-encoded wasm + compile logs.
- `POST /build` — compile to a native Linux **x86_64 ELF** (clang +
  `stdlib/runtime.native.o`). Returns build logs plus expiring download
  URLs for the `.ll` and the binary.
- `POST /build_windows` — cross-compile to a Windows **x86_64 `.exe`** via
  mingw-w64. Runtime is pre-built with static libcurl (Schannel TLS) so HTTP
  works end-to-end; canvas/audio FFIs are rejected up front.
- `POST /build_macos` — cross-compile to a macOS **x86_64 Mach-O** via `zig
  cc`. Links only libSystem; unsigned (clear the quarantine attribute before
  running). Thin wrapper over `/build_target`.
- `POST /build_target` — cross-compile to any registered **zig target**:
  `linux-{x64,arm64,riscv64}-musl` (fully-static ELF), `linux-arm64-gnu`
  (dynamic glibc), `macos-{x64,arm64}` (Mach-O incl. native Apple Silicon).
  Body adds `"target":"<id>"`. canvas/audio/HTTP unsupported on these targets.
- `POST /build_unikernel` — build a **bootable unikernel image**: the
  program compiled freestanding (unikernel nolibc + `runtime_bare`, no
  host OS) into an x86_64 PVH ELF (QEMU microvm; the same image boots
  under Firecracker and cloud-hypervisor) or, with `"arch":"aarch64"`,
  an ELF + flat `Image` for QEMU `virt`. Optional `"args"` (the guest's
  argv — returned inside the boot command, never executed server-side),
  `"files"` (`{relative/path: base64}` baked in as a read-only
  filesystem) and `"boot": true` (boot the image server-side and return
  the guest console + exit status). The reply carries the artifact plus
  ready-to-paste QEMU commands. The same build is exposed to agents as
  MCP tool `nurl_build_unikernel`.
  **Target** dropdown is built from this).
- `GET /download/{build_id}/{filename}` — stream a build artifact
  produced by a `/build*` endpoint. Artifacts expire automatically
  (TTL sweep, default 1 h).
- `GET /examples`, `GET /examples/{name}` — list / fetch bundled examples.
- `GET /grammar` — current grammar rendered as HTML (from `spec/grammar.ebnf`).
- `GET /readme` — this project's README rendered as HTML.
- `GET /openapi.json` — OpenAPI 3.1 schema; `GET /docs` — Swagger UI.

The endpoint set is authoritative in `GET /openapi.json` (Swagger UI at
`/docs`).

## Build & run the container

From the **repository root** (the build context must be the repo root so the
Dockerfile can reach `build.sh`, `compiler/`, `stdlib/`, `examples/`,
`spec/`, `README.md`):

```bash
docker build -f nurlapi/Dockerfile -t nurl-api:dev .
docker run --rm -p 8000:8000 nurl-api:dev
# → http://localhost:8000/         (playground)
# → http://localhost:8000/docs     (Swagger UI)
# → http://localhost:8000/mcp      (MCP endpoint)
```

Or run the server binary directly without Docker, using the host's `nurlc`
and stdlib:

```bash
./nurl.sh nurlapi/main.nu nurlapi/nurlapi
./nurlapi/nurlapi   # listens on 0.0.0.0:8000
```

See [`nurlapi/README.md`](../nurlapi/README.md) for image details and
environment variables.

## Pipeline inside the container

1. `nurlc <file.nu>` → LLVM IR on stdout.
2. The API rewrites the IR to match the `wasm32-wasi` ABI (renames `@main` →
   `@__main_argc_argv`, injects the target triple, inserts i32/i64 shims for
   `malloc`/`puts` to match libc signatures).
3. `clang --target=wasm32-wasi -O2 <ir>.ll /opt/nurl/stdlib/runtime.wasm.o -o
   out.wasm` using the bundled WASI SDK (24.0).

The wasm-compiled NURL runtime (`stdlib/runtime.wasm.o`) is baked into the
image at build time.

## Compiler-in-wasm (offline / embeddable)

The same `POST /build_wasm` pipeline can be pointed at `compiler/nurlc.nu`
itself, producing a `nurlc.wasm` that **is** the NURL compiler:

```bash
./startdev.sh        # one terminal: bring up the API container
./buildwasm.sh       # → ./nurlc.wasm  (POSTs nurlc.nu to /build_wasm)
./wasmnurl.sh examples/showcase.nu   # uses nurlc.wasm under wasmtime
```

Once built, `nurlc.wasm` runs anywhere a WASI host does — `wasmtime`,
`wasmer`, Node's WASI, or a browser shim. The bootstrap is closed:
`nurlc.wasm` re-compiling its own source produces byte-identical IR to the
native `nurlc`, so the wasm path is a faithful copy of the compiler — a
lightweight regression check on cross-ABI codegen.

## MCP server — let an LLM drive the toolchain

The playground container also exposes the toolchain as a **public,
unauthenticated [Model Context Protocol](https://modelcontextprotocol.io/)**
endpoint, mounted at `/mcp` over Streamable HTTP. The JSON-RPC handler,
framing and tool/resource catalog are pure NURL
([`nurlapi/main.nu`](../nurlapi/main.nu) backed by
`stdlib/ext/mcp_server.nu` — the one server framework every MCP server in
the tree is built on — over `packages/http`).

**Add to Claude Code / Claude Desktop:**
```bash
claude mcp add --transport http nurl https://play.nurl-lang.org/mcp
```
Cursor, Windsurf, Zed and other MCP-capable IDEs accept the same URL
(transport: `http` / `streamable-http`).

**What's on offer** — the live catalog is authoritative; broadly:
- **Tools** to act on NURL source: *build* (compile + return artifact for
  native Linux / Windows / macOS / cross targets / wasm), *browse* (list
  examples, stdlib, tests), and *read* (examples, stdlib, tests, grammar,
  readme, roadmap).
- **Search** — `nurl_api` (a module's or a registry package's API surface,
  or a term search over every stdlib declaration) and `nurl_grep` (ranked
  substring search across stdlib, examples, tests and the registry).
  A `nurl_api` query no single declaration satisfies is re-run as a
  whole-word OR ranked by coverage, so a concept-shaped query — the kind a
  model actually types, `string builder append` or `vec_push new
  string_new` — lands on the real functions instead of an empty result.
- **`nurl_docs`** — this documentation tree, the questions the API surface
  cannot answer: `MEMORY.md` (who frees what, and when), `CRYPTO.md`,
  `ASYNC.md`, `PLATFORMS.md`, `spec.md`, `dev/COMPILER_INTERNALS.md`, …
  No argument lists everything with its size and title. `query=` searches
  every **section** of every document and hands back the best few with the
  keys to fetch them; `name=X outline=true` is one document's heading map;
  `name=X section='7.4'` is one section — a few KB rather than MEMORY.md's
  44 KB, and the only way to read part of `spec.md`, which exceeds the
  per-call cap. `name=` alone still returns the whole document, `offset=`
  pages it.
- **Resources** mirroring the read-tools as `nurl://` URIs (`nurl://grammar`,
  `nurl://readme`, `nurl://stdlib/<path>`, `nurl://example/<name>`, …) for
  clients that prefer resource semantics.
- A **prompt** (`nurl_coding_assistant`) — a compact grammar + canonical
  example primer that grounds smaller models before they write NURL.

**Self-host:** the `/mcp` mount comes for free with the container above, or
run the server binary directly. `nurlapi/main.nu` is a NURL program — no
Python or Node runtime involved.

**Asking the compiler to check harder.** Every build tool takes `flags`,
a space-separated string of nurlc flags from a fixed allow-list:

| Flag | What it does |
|---|---|
| `--lint` | report an allocation nothing owns (docs/MEMORY.md §1) |
| `--no-borrowck` | compile with the borrow checker off |
| `--strict-borrowck` | the stricter §2.4 argument rules |
| `--no-strict-arity` | accept the n-ary `&` / `\|` spellings |
| `--no-cpu-dispatch` | no x86-64-v3 clone for `simd` functions |

`--lint`'s findings arrive in `nurlc_stderr` of an ordinary successful
build, so a lint run is a normal build you read the stderr of. It is an
allow-list rather than a passthrough because nurlc also takes `--keep=`
and `--split-out=`, which name paths inside the container; anything not
on the list is a 400 naming what is, never a silently dropped flag.

**Running what you built.** `nurl_build_native` takes `run=true` to
execute the program and return its exit code, stdout and stderr in the
same call — one round trip from source to output. It is **off** on the
hosted instance and returns an error saying so, because executing a
freshly compiled binary is unsandboxed: it gets the container's
filesystem, network and environment. A self-hosted deployment enables it
with `NURL_ALLOW_RUN=1`, the same switch and the same reasoning as
`nurl-mcp --allow-run` over HTTP.

The sandboxed way to see output needs no switch: `nurl_build_unikernel`
boots the program as its own kernel under QEMU, with no network and a
time cap, and hands back the guest console.

**Caveats:**
- Open and unauthenticated. The hosted instance is a free public endpoint —
  don't push secrets through it; assume the source is logged. For
  trust-sensitive use, self-host.
- Build endpoints run arbitrary NURL source through `clang` inside the
  container. Container-level sandboxing is the only isolation; downstream
  binaries are returned, not executed.
- The tool/resource catalog tracks `main`. Breaking changes to a tool
  signature are announced in [`CHANGELOG.md`](../CHANGELOG.md).
