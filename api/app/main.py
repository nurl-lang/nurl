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

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from app.build_routes import create_build_router
from app.config import ApiConfig, load_api_config
from app.system_routes import create_system_router, mount_static_playground


@asynccontextmanager
async def _lifespan(app: FastAPI):
    """Drive the MCP server's session manager for the lifetime of the app."""

    del app
    from app.mcp_server import mcp

    async with mcp.session_manager.run():
        yield


def create_app(config: ApiConfig | None = None) -> FastAPI:
    config = config or load_api_config()
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

    app.include_router(create_build_router(config.build))
    app.include_router(
        create_system_router(
            nurlc_path=config.nurlc_path,
            nurl_zig=config.nurl_zig,
            runtime_wasm_o=config.runtime_wasm_o,
            stdlib_dir=config.stdlib_dir,
        )
    )

    from app.content_routes import router as _content_router  # noqa: E402
    from app.mcp_compat import (  # noqa: E402
        mcp_client_compat_middleware,
        router as _mcp_compat_router,
    )
    from app.mcp_server import mcp as _mcp  # noqa: E402
    from app.rest_mcp import router as _rest_mcp_router  # noqa: E402

    app.include_router(_content_router)
    app.include_router(_rest_mcp_router)
    app.include_router(_mcp_compat_router)

    @app.exception_handler(HTTPException)
    async def _http_exc_handler(_request, exc: HTTPException):
        return JSONResponse(
            status_code=exc.status_code,
            content={"status": "error", "detail": exc.detail},
        )

    mount_static_playground(app, config.static_dir)
    app.mount("/", _mcp.streamable_http_app())
    app.middleware("http")(mcp_client_compat_middleware)
    return app


app = create_app()
