# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""NURL HTTP API app assembly.

The build execution layer lives in dedicated routers/modules:
  - app.build_routes: compile/link endpoints and artifact downloads
  - app.system_routes: health checks and static playground mounting
  - app.content_routes: examples, stdlib, docs, and MCP info
  - app.mcp_compat / app.rest_mcp / app.mcp_server: MCP-facing surfaces
"""

from __future__ import annotations

import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from app.build_routes import BuildConfig, create_build_router
from app.system_routes import create_system_router, mount_static_playground


NURLC_PATH = os.environ.get("NURLC_PATH", "/opt/nurl/build/nurlc")
WASM_TARGET = os.environ.get("NURL_WASM_TARGET", "wasm32-wasi")
RUNTIME_WASM_O = os.environ.get(
    "NURL_RUNTIME_WASM_O", "/opt/nurl/stdlib/runtime.wasm.o"
)
CANVAS_WASM_O = os.environ.get(
    "NURL_CANVAS_WASM_O", "/opt/nurl/stdlib/canvas.wasm.o"
)
AUDIO_WASM_O = os.environ.get(
    "NURL_AUDIO_WASM_O", "/opt/nurl/stdlib/audio.wasm.o"
)
WASM_OPT = os.environ.get("NURL_WASM_OPT", "wasm-opt")
NURL_WORK_ROOT = os.environ.get("NURL_WORK_ROOT", "/opt/nurl")
NURL_STDLIB_DIR = os.environ.get("NURL_STDLIB_DIR", "/opt/nurl/stdlib")
STATIC_DIR = os.environ.get(
    "NURL_API_STATIC_DIR", str(Path(__file__).resolve().parent.parent / "static")
)
BUILD_TIMEOUT_SEC = int(os.environ.get("NURL_BUILD_TIMEOUT_SEC", "30"))
MAX_SOURCE_BYTES = int(
    os.environ.get("NURL_MAX_SOURCE_BYTES", str(1 * 1024 * 1024))
)


def _default_runtime_o() -> str:
    native = "/opt/nurl/stdlib/runtime.native.o"
    return native if Path(native).is_file() else "/opt/nurl/stdlib/runtime.o"


NATIVE_CLANG = os.environ.get(
    "NURL_NATIVE_CLANG",
    "/usr/bin/clang" if Path("/usr/bin/clang").exists() else "clang",
)
RUNTIME_O = os.environ.get("NURL_RUNTIME_O", _default_runtime_o())
CANVAS_O = os.environ.get("NURL_CANVAS_O", "/opt/nurl/stdlib/canvas.o")
NURL_LINK_HELPER = os.environ.get("NURL_LINK_HELPER", "/opt/nurl/build/nurl-build")
WINDOWS_TARGET = os.environ.get("NURL_WINDOWS_TARGET", "x86_64-windows-gnu")
RUNTIME_WIN_O = os.environ.get(
    "NURL_RUNTIME_WIN_O", "/opt/nurl/stdlib/runtime.win.o"
)
NURL_ZIG = os.environ.get("NURL_ZIG", "/opt/zig/zig")
MACOS_TARGET = os.environ.get("NURL_MACOS_TARGET", "x86_64-macos-none")
RUNTIME_MAC_O = os.environ.get(
    "NURL_RUNTIME_MAC_O", "/opt/nurl/stdlib/runtime.mac.o"
)
CANVAS_SDL2_MARKER = os.environ.get(
    "NURL_CANVAS_SDL2_MARKER", "/opt/nurl/stdlib/canvas.sdl2"
)
OUTPUT_DIR = os.environ.get("NURL_OUTPUT_DIR", "/app/output")
DOWNLOAD_TTL_SEC = int(os.environ.get("NURL_DOWNLOAD_TTL_SEC", str(60 * 60)))


@asynccontextmanager
async def _lifespan(app: FastAPI):
    """Drive the MCP server's session manager for the lifetime of the app."""

    del app
    from app.mcp_server import mcp

    async with mcp.session_manager.run():
        yield


app = FastAPI(
    title="NURL Compiler API",
    description=(
        "HTTP interface to the NURL compiler.\n\n"
        "Compiles NURL source to native x86_64 binaries (`POST /build`) "
        "or wasm32-wasi WebAssembly (`POST /build_wasm`), serves the "
        "in-browser playground at `/`, and exposes the same surface as "
        "a **Model Context Protocol** server at `POST /mcp` "
        "(Streamable HTTP transport) for LLM clients. "
        "See `GET /mcp-info` for MCP connection details — the MCP "
        "endpoint itself is an ASGI sub-app so its JSON-RPC methods "
        "aren't enumerated in this OpenAPI schema."
    ),
    version="0.1.0",
    lifespan=_lifespan,
)


app.include_router(
    create_build_router(
        BuildConfig(
            nurlc_path=NURLC_PATH,
            wasm_target=WASM_TARGET,
            runtime_wasm_o=RUNTIME_WASM_O,
            canvas_wasm_o=CANVAS_WASM_O,
            audio_wasm_o=AUDIO_WASM_O,
            wasm_opt=WASM_OPT,
            nurl_work_root=NURL_WORK_ROOT,
            build_timeout_sec=BUILD_TIMEOUT_SEC,
            max_source_bytes=MAX_SOURCE_BYTES,
            native_clang=NATIVE_CLANG,
            runtime_o=RUNTIME_O,
            canvas_o=CANVAS_O,
            link_helper=NURL_LINK_HELPER,
            windows_target=WINDOWS_TARGET,
            runtime_win_o=RUNTIME_WIN_O,
            nurl_zig=NURL_ZIG,
            macos_target=MACOS_TARGET,
            runtime_mac_o=RUNTIME_MAC_O,
            canvas_sdl2_marker=CANVAS_SDL2_MARKER,
            output_dir=OUTPUT_DIR,
            download_ttl_sec=DOWNLOAD_TTL_SEC,
        )
    )
)
app.include_router(
    create_system_router(
        nurlc_path=NURLC_PATH,
        nurl_zig=NURL_ZIG,
        runtime_wasm_o=RUNTIME_WASM_O,
        stdlib_dir=NURL_STDLIB_DIR,
    )
)


from app.content_routes import router as _content_router  # noqa: E402

app.include_router(_content_router)


@app.exception_handler(HTTPException)
async def _http_exc_handler(_request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"status": "error", "detail": exc.detail},
    )


mount_static_playground(app, STATIC_DIR)


from app.rest_mcp import router as _rest_mcp_router  # noqa: E402
from app.mcp_compat import (  # noqa: E402
    mcp_client_compat_middleware,
    router as _mcp_compat_router,
)
from app.mcp_server import mcp as _mcp  # noqa: E402

app.include_router(_rest_mcp_router)
app.include_router(_mcp_compat_router)
app.mount("/", _mcp.streamable_http_app())
app.middleware("http")(mcp_client_compat_middleware)
