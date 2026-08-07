  # NURL - Neural Unified Representation Language

  Self-hosted compiler for the **NURL** programming language, packaged with a pure-NURL HTTP API server, a Monaco-based browser playground, and a Model
  Context Protocol (MCP) server — all in one image. No Python; the playground server itself is a NURL program (`nurlapi/main.nu`).

  NURL is a terse prefix-notation systems language that lowers to LLVM IR. See
  [github.com/nurl-lang/nurl](https://github.com/nurl-lang/nurl) for the language reference.

  ## What's inside

  - **`nurlc`** — the self-hosted NURL compiler (bootstrapped `nurlc_lastgood.ll → nurlc_lastgood.bin → nurlc_self → nurlc_self2`; clang-only, no Python).
  - **Cross-compilation toolchains**, all preinstalled:
    - **Linux** x86_64 ELF — `clang-16` + glibc, full FFI (HTTP / sqlite / canvas)
    - **Linux** cross — `zig cc`: `x86_64` / `aarch64` / `riscv64` musl (static),
      `aarch64` glibc. libc only; no HTTP/canvas/audio
    - **macOS** Mach-O — `zig cc`, Intel **and** Apple Silicon (libSystem only; no Cocoa/AudioToolbox)
    - **Windows** `.exe` — `mingw-w64` + statically-linked `libcurl` (Schannel TLS, no DLLs to ship)
    - **WebAssembly** — WASI SDK 24 + `wasm-opt` (binaryen) for Asyncify
  - **Pure-NURL HTTP API** (`nurlapi/main.nu`, compiled to a native binary at image-build time) with `/build`, `/build_wasm`, `/build_windows`,
    `/build_macos`, `/build_target`, `/build_unikernel` (a bootable
    unikernel image — x86_64 PVH/microvm by default, AArch64 QEMU virt
    via `arch` — plus ready-to-paste QEMU boot commands; `files` bakes
    a read-only filesystem into the image, `boot: true` boots it
    server-side and returns the guest console; also exposed as MCP tool
    `nurl_build_unikernel`) build endpoints and `/targets` (the
    cross-compile target registry the playground's dropdown is built from). HTTP server, router, JSON, MCP transport — all stdlib (`stdlib/ext/http_*.nu`, `stdlib/ext/json.nu`, `stdlib/ext/mcp_*.nu`).
  - **Browser playground** at `/` — Monaco editor, examples dropdown, build+run in-page via
  [`@bjorn3/browser_wasi_shim`](https://github.com/bjorn3/browser_wasi_shim).
  - **MCP server** at `/mcp` (Streamable HTTP) — tools, resources, prompts for Claude Desktop, Cursor, Windsurf, Zed.
  - **Bundled assets**: stdlib, examples, compiler test suite, EBNF grammar, README, ROADMAP, GOTCHAS.
  - **OpenAPI 3.1** at `/openapi.json`, Swagger UI at `/docs`.

  ## Quick start

  ```bash
  docker run --rm -p 8000:8000 <your-namespace>/nurl:latest
  ```

  Then open:

  - <http://localhost:8000/> — playground
  - <http://localhost:8000/docs> — Swagger UI
  - <http://localhost:8000/health> — liveness probe
  - <http://localhost:8000/mcp> — MCP endpoint

  ## Build a binary via HTTP

  ```bash
  curl -s -X POST http://localhost:8000/build_wasm \
    -H 'Content-Type: application/json' \
    -d '{"source":"@ main → i { ^ 0 }\n","return_format":"binary"}' \
    -o main.wasm
  wasmtime main.wasm
  ```

  ## MCP client config

  ```json
  {
    "mcpServers": {
      "nurl": {
        "url": "http://localhost:8000/mcp",
        "transport": "streamable-http"
      }
    }
  }
  ```

  ## Image details

  | | |
  |---|---|
  | **Base image** | `debian:bookworm-slim` (multi-stage; no Python in the runtime stage) |
  | **Server binary** | `/app/nurlapi` — native NURL build of `nurlapi/main.nu` (~stripped, statically links the NURL runtime) |
  | **Exposed port** | `8000` |
  | **Liveness probe** | `GET /health` (no Docker `HEALTHCHECK` directive — wire one up in your orchestrator) |
  | **Supported arch** | `linux/amd64` |
  | **WASI SDK** | 24.0 |
  | **Zig** | 0.13.0 |
  | **libcurl (mingw)** | 8.10.1, static, Schannel |

  ## Environment variables

  Common overrides — full list in `nurlapi/main.nu` (search for `env_var_or`):

  | Var | Default | Purpose |
  |---|---|---|
  | `NURL_API_URL` | `http://localhost:8000` | API base URL for MCP server |
  | `NURLC_PATH` | `/opt/nurl/build/nurlc` | Self-hosted compiler |
  | `NURL_WORK_ROOT` | `/opt/nurl` | Temp/working files |
  | `NURL_DOWNLOAD_TTL_SEC` | `3600` | Artifact download TTL |

  ## Tags

  - `latest` — latest stable release
  - `vX.Y.Z` — pinned release (matches NURL `vX.Y.Z`)

  ## Source & license

  - **Source**: <https://github.com/nurl-lang/nurl>
  - **License**: dual-licensed **MIT OR Apache-2.0**