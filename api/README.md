# NURL API

FastAPI-based HTTP interface to the NURL compiler (grammar **v1.1**),
bundled with a Monaco-based browser playground that runs compiled wasm
in-page via [`@bjorn3/browser_wasi_shim`](https://github.com/bjorn3/browser_wasi_shim).

The container bootstraps the NURL compiler from source (via the repo's
`build.sh`), installs the WASI SDK, and ships both alongside the Python API.

## Endpoints

### Playground & UI
- `GET /` — Monaco-based NURL playground: editor with syntax highlighting,
  examples dropdown, build-to-wasm + run-in-browser + download buttons.
- `GET /favicon.svg` — favicon.
- `GET /static/*` — playground assets.

### Compiler
- `POST /build_wasm` — compile NURL source to `wasm32-wasi`.
  Body: `{"source":"...","filename":"main.nu","return_format":"json"|"binary","emit_ll":false}`.
  JSON mode returns base64-encoded wasm + compile logs; binary mode returns
  raw `application/wasm` bytes. `emit_ll: true` also returns the intermediate
  (post-rewrite) LLVM IR for debugging.
- `POST /build` — compile NURL source to a **native** Linux binary (mirrors
  `nurl.sh` inside the container). Body:
  `{"source":"...","filename":"main.nu","opt":"-O2"}`. Artifacts (`.ll` and
  the binary) are written to `/app/output` and returned as download URLs
  along with `stdout`/`stderr` from `nurlc` and `clang`.
- `GET /download/{token}` — download an artifact produced by `/build`.
  Tokens expire after `NURL_DOWNLOAD_TTL_SEC` (default 1 h).

### Examples & docs
- `GET /examples` — JSON list of bundled `.nu` examples.
- `GET /examples/{name}` — source of a specific example (e.g. `enigma.nu`).
- `GET /grammar` — current grammar rendered as HTML (from `spec/grammar.ebnf`).
- `GET /readme` — the repo's top-level `README.md` rendered as HTML.

### MCP (Model Context Protocol)
- `POST /mcp` — Streamable HTTP endpoint for MCP clients (Claude Desktop,
  Cursor, Windsurf, Zed, etc.). Exposes:
  - **Tools**: `nurl_build_native`, `nurl_build_wasm`, `nurl_list_examples`,
    `nurl_read_example`, `nurl_list_stdlib`.
  - **Resources**: `nurl://grammar`, `nurl://readme`,
    `nurl://stdlib/{path}`, `nurl://example/{name}`.
  - **Prompts**: `nurl_coding_assistant`.

  Example client config (Claude Desktop / Cursor / Windsurf
  `mcp.json`):
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

### Introspection
- `GET /health` — liveness probe; reports whether `nurlc` is available.
- `GET /docs` — Swagger UI.
- `GET /redoc` — ReDoc.
- `GET /openapi.json` — OpenAPI schema.

## Build & run

From the **repository root** (the build context must be the repo root so
the Dockerfile can access `build.sh`, `compiler/`, `stdlib/`, `examples/`,
`spec/`, `README.md`, `favicon.svg`):

```bash
docker build -f api/Dockerfile -t nurl-api:dev .
docker run --rm -p 8000:8000 nurl-api:dev
```

Then open:

- http://localhost:8000/         — playground
- http://localhost:8000/health   — liveness
- http://localhost:8000/docs     — Swagger UI
- http://localhost:8000/grammar  — grammar v1.1
- http://localhost:8000/readme   — rendered top-level README

## Example

```bash
curl -s http://localhost:8000/health | jq

curl -s -X POST http://localhost:8000/build_wasm \
  -H 'Content-Type: application/json' \
  -d '{"source":"@ main → i { return 0 }\n","filename":"main.nu"}' | jq

# Download the raw .wasm directly:
curl -s -X POST http://localhost:8000/build_wasm \
  -H 'Content-Type: application/json' \
  -d '{"source":"@ main → i { return 0 }\n","return_format":"binary"}' \
  -o main.wasm
wasmtime main.wasm

# Native build (ELF binary, runs inside the container's glibc):
RESP=$(curl -s -X POST http://localhost:8000/build \
  -H 'Content-Type: application/json' \
  -d '{"source":"@ main → i { return 0 }\n","filename":"main.nu"}')
echo "$RESP" | jq
BIN_URL=$(echo "$RESP" | jq -r '.binary_artifact.download_url')
LL_URL=$(echo  "$RESP" | jq -r '.ll_artifact.download_url')
curl -s -o main    "$BIN_URL" && chmod +x main
curl -s -o main.ll "$LL_URL"
```

## Pipeline

1. `nurlc <file.nu>` → LLVM IR on stdout.
2. The API rewrites the IR to match the `wasm32-wasi` ABI:
   - renames `@main` → `@__main_argc_argv` (WASI entry-point convention),
   - injects the `wasm32-wasi` target triple,
   - inserts i32/i64 shims for `malloc` and `puts` so NURL's i64-centric
     signatures line up with libc's i32 wasm ABI.
3. `clang --target=wasm32-wasi -O2 <ir>.ll /opt/nurl/stdlib/runtime.wasm.o -o out.wasm`
   using the WASI SDK (24.0) bundled into the image.

The wasm-compiled NURL runtime (`stdlib/runtime.wasm.o`) is baked into the
image at build time.

## Environment variables

The API reads these at startup (defaults shown match the Dockerfile):

| Var | Default | Purpose |
|---|---|---|
| `NURLC_PATH` | `/opt/nurl/build/nurlc` | Self-hosted compiler binary |
| `WASI_CLANG` | `/opt/wasi-sdk/bin/clang` | Clang from the bundled WASI SDK |
| `NURL_RUNTIME_WASM_O` | `/opt/nurl/stdlib/runtime.wasm.o` | Pre-built wasm runtime object |
| `NURL_WORK_ROOT` | `/opt/nurl` | Working root for temp files |
| `NURL_STDLIB_DIR` | `/opt/nurl/stdlib` | Stdlib source dir |
| `NURL_EXAMPLES_DIR` | `/opt/nurl/examples` | Served by `/examples` |
| `NURL_GRAMMAR_PATH` | `/opt/nurl/spec/grammar.ebnf` | Served by `/grammar` |
| `NURL_README_PATH` | `/opt/nurl/README.md` | Served by `/readme` |
| `STATIC_DIR` | `/opt/nurl/api/static` | Playground assets |

## Local dev (without Docker)

```bash
pip install -r api/requirements.txt
NURLC_PATH="$PWD/build/nurlc" uvicorn app.main:app --reload --app-dir api
```
