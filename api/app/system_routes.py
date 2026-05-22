# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""System-level API routes and static playground mounting."""

from __future__ import annotations

import os
import shutil
from pathlib import Path

from fastapi import APIRouter, FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str = Field(..., examples=["ok"])
    nurlc_available: bool = Field(
        ..., description="Whether the bundled nurlc binary is present and executable."
    )
    nurlc_path: str
    wasi_toolchain_available: bool
    stdlib_available: bool
    stdlib_dir: str
    stdlib_modules: list[str] = Field(
        default_factory=list,
        description="Relative paths of .nu files discovered under the stdlib dir.",
    )


def _is_executable(path: str) -> bool:
    target = Path(path)
    return target.is_file() and os.access(target, os.X_OK)


def _list_stdlib_modules(stdlib_dir: str, limit: int = 200) -> list[str]:
    root = Path(stdlib_dir)
    if not root.is_dir():
        return []
    modules = sorted(str(path.relative_to(root)) for path in root.rglob("*.nu"))
    return modules[:limit]


def create_system_router(
    *,
    nurlc_path: str,
    nurl_zig: str,
    runtime_wasm_o: str,
    stdlib_dir: str,
) -> APIRouter:
    router = APIRouter()

    def _nurlc_available() -> bool:
        return _is_executable(nurlc_path) or shutil.which("nurlc") is not None

    def _wasi_toolchain_available() -> bool:
        return ((shutil.which(nurl_zig) is not None or _is_executable(nurl_zig))
                and Path(runtime_wasm_o).is_file())

    @router.get("/health", response_model=HealthResponse, tags=["system"])
    def health() -> HealthResponse:
        return HealthResponse(
            status="ok",
            nurlc_available=_nurlc_available(),
            nurlc_path=nurlc_path,
            wasi_toolchain_available=_wasi_toolchain_available(),
            stdlib_available=Path(stdlib_dir).is_dir(),
            stdlib_dir=stdlib_dir,
            stdlib_modules=_list_stdlib_modules(stdlib_dir),
        )

    return router


def mount_static_playground(app: FastAPI, static_dir: str) -> None:
    static_root = Path(static_dir)
    if not static_root.is_dir():
        return

    app.mount("/static", StaticFiles(directory=str(static_root)), name="static")

    @app.get("/", include_in_schema=False)
    def root() -> FileResponse:
        return FileResponse(str(static_root / "index.html"))

    @app.get("/favicon.ico", include_in_schema=False)
    @app.get("/favicon.svg", include_in_schema=False)
    def favicon() -> FileResponse:
        path = static_root / "favicon.svg"
        if not path.is_file():
            raise HTTPException(status_code=404, detail="favicon not found")
        return FileResponse(str(path), media_type="image/svg+xml")
