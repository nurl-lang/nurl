  # NURL - Neural Unified Representation Language (Or **N**on h**U**man **R**eadable **L**anguage)

  Self-hosted compiler for the **NURL** programming language, packaged with a FastAPI HTTP API, a Monaco-based browser playground, and a Model
  Context Protocol (MCP) server — all in one image.

  NURL is a terse prefix-notation systems language that lowers to LLVM IR. See
  [github.com/nurl-lang/nurl](https://github.com/nurl-lang/nurl) for the language reference.

  ## What's inside

  - **`nurlc`** — the self-hosted NURL compiler (bootstrapped `python → nurlc_py → nurlc_self → nurlc_self2`).
  - **Cross-compilation toolchains**, all preinstalled:
    - **Linux** ELF — `clang-16` + glibc
    - **Windows** `.exe` — `zig cc` (x86_64-windows-gnu) + statically-linked `libcurl` (Schannel TLS, no DLLs to ship)
    - **macOS** x86_64 Mach-O — `zig cc` with bundled libSystem stubs (libSystem only; no Cocoa/AudioToolbox)
    - **WebAssembly** — `zig cc` (wasm32-wasi) + `wasm-opt` (binaryen) for Asyncify
  - **FastAPI HTTP API** with `/build`, `/build_wasm`, `/build_windows`, `/build_macos` endpoints.
  - **Browser playground** at `/` — Monaco editor, examples dropdown, build+run in-page via
  [`@bjorn3/browser_wasi_shim`](https://github.com/bjorn3/browser_wasi_shim).
  - **MCP server** at `/mcp` (Streamable HTTP) — tools, resources, prompts for Claude Desktop, Cursor, Windsurf, Zed.
  - **Bundled assets**: stdlib, examples, compiler test suite, EBNF grammar, README, ROADMAP, GOTCHAS.
  - **OpenAPI** at `/docs` (Swagger UI), `/redoc`, `/openapi.json`.

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
  | **Base image** | `python:3.12-slim-bookworm` |
  | **Exposed port** | `8000` |
  | **User** | non-root (`nurl`, uid 1001) |
  | **Healthcheck** | `GET /health` every 30 s |
  | **Supported arch** | `linux/amd64`, `linux/arm64` |
  | **Zig** | 0.16.0 (unified cross-compiler: Windows / macOS / wasm) |
  | **libcurl** | 8.10.1, static, Schannel (cross-built with `zig cc`) |

  ## Environment variables

  Common overrides — full list in the [api README](https://github.com/nurl-lang/nurl/blob/main/api/README.md):

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