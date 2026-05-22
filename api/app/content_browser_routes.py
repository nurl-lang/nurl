# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""Read-only routes for examples, tests, and stdlib browsing."""

from __future__ import annotations

import os
from pathlib import Path

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import FileResponse
from pydantic import BaseModel

from app.mcp_catalog import NURL_EXAMPLES_DIR, NURL_STDLIB_DIR, NURL_TESTS_DIR


router = APIRouter()
STATIC_DIR = Path(
    os.environ.get(
        "NURL_API_STATIC_DIR",
        str(Path(__file__).resolve().parent.parent / "static"),
    )
)


class ExampleInfo(BaseModel):
    name: str
    path: str
    bytes: int


class ExampleContent(BaseModel):
    name: str
    source: str
    bytes: int


class TestInfo(BaseModel):
    name: str
    path: str
    bytes: int


class TestContent(BaseModel):
    name: str
    source: str
    bytes: int


class StdlibInfo(BaseModel):
    name: str
    path: str
    bytes: int


class StdlibContent(BaseModel):
    name: str
    source: str
    bytes: int


def _list_nu_files(root_dir: str) -> list[dict]:
    root = Path(root_dir)
    if not root.is_dir():
        return []
    out: list[dict] = []
    for path in sorted(root.rglob("*.nu")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        try:
            size = path.stat().st_size
        except OSError:
            continue
        out.append({"name": rel, "path": rel, "bytes": size})
    return out


def _safe_under(base_dir: str, name: str, *, label: str) -> Path:
    root = Path(base_dir).resolve()
    target = (root / name).resolve()
    if root not in target.parents and target != root:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"invalid {label} path",
        )
    if not target.is_file() or target.suffix != ".nu":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"{label} not found",
        )
    return target


@router.get("/examples", response_model=list[ExampleInfo], tags=["examples"])
def list_examples() -> list[ExampleInfo]:
    return [ExampleInfo(**entry) for entry in _list_nu_files(NURL_EXAMPLES_DIR)]


@router.get("/examples/{name:path}", response_model=ExampleContent, tags=["examples"])
def get_example(name: str) -> ExampleContent:
    target = _safe_under(NURL_EXAMPLES_DIR, name, label="example")
    source = target.read_text(encoding="utf-8", errors="replace")
    return ExampleContent(name=name, source=source, bytes=len(source.encode("utf-8")))


@router.get("/tests", response_model=list[TestInfo], tags=["tests"])
def list_tests() -> list[TestInfo]:
    return [TestInfo(**entry) for entry in _list_nu_files(NURL_TESTS_DIR)]


@router.get("/tests/{name:path}", response_model=TestContent, tags=["tests"])
def get_test(name: str) -> TestContent:
    target = _safe_under(NURL_TESTS_DIR, name, label="test")
    source = target.read_text(encoding="utf-8", errors="replace")
    return TestContent(name=name, source=source, bytes=len(source.encode("utf-8")))


def _viewer_asset(name: str) -> Path:
    path = STATIC_DIR / name
    if not path.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"viewer asset not found: {name}",
        )
    return path


@router.get(
    "/stdlib-viewer",
    response_class=FileResponse,
    tags=["stdlib"],
    include_in_schema=False,
    summary="Browsable Monaco-highlighted viewer for stdlib modules",
)
def stdlib_viewer() -> FileResponse:
    return FileResponse(_viewer_asset("stdlib-viewer.html"))


@router.get("/stdlib", response_model=list[StdlibInfo], tags=["stdlib"])
def list_stdlib() -> list[StdlibInfo]:
    return [StdlibInfo(**entry) for entry in _list_nu_files(NURL_STDLIB_DIR)]


@router.get("/stdlib/{name:path}", response_model=StdlibContent, tags=["stdlib"])
def get_stdlib_module(name: str) -> StdlibContent:
    target = _safe_under(NURL_STDLIB_DIR, name, label="stdlib module")
    source = target.read_text(encoding="utf-8", errors="replace")
    return StdlibContent(name=name, source=source, bytes=len(source.encode("utf-8")))


@router.get(
    "/tests-viewer",
    response_class=FileResponse,
    tags=["tests"],
    include_in_schema=False,
    summary="Browsable Monaco-highlighted viewer for compiler tests",
)
def tests_viewer() -> FileResponse:
    return FileResponse(_viewer_asset("tests-viewer.html"))
