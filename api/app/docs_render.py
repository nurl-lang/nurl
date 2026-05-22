# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""Shared document rendering helpers for read-only docs routes."""

from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

import markdown as _md
from fastapi import HTTPException, status
from fastapi.responses import HTMLResponse, PlainTextResponse


STATIC_DIR = Path(
    os.environ.get(
        "NURL_API_STATIC_DIR",
        str(Path(__file__).resolve().parent.parent / "static"),
    )
)


def read_text_file(path_str: str, label: str) -> str:
    path = Path(path_str)
    if not path.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"{label} not found",
        )
    return path.read_text(encoding="utf-8", errors="replace")


def raw_text_response(path_str: str, label: str) -> PlainTextResponse:
    return PlainTextResponse(read_text_file(path_str, label))


@lru_cache(maxsize=1)
def _doc_page_template() -> str:
    template_path = STATIC_DIR / "doc-page-template.html"
    if not template_path.is_file():
        raise RuntimeError(f"missing doc page template: {template_path}")
    return template_path.read_text(encoding="utf-8")


def render_doc_page(*, title: str, body_html: str, raw_path: str) -> str:
    return (
        _doc_page_template()
        .replace("__TITLE__", title)
        .replace("__RAW_PATH__", raw_path)
        .replace("__CONTENT__", body_html)
    )


def render_markdown_page(
    *,
    title: str,
    text: str,
    raw_path: str,
    extensions: list[str],
    extension_configs: dict | None = None,
) -> HTMLResponse:
    html = _md.markdown(
        text,
        extensions=extensions,
        extension_configs=extension_configs or {},
        output_format="html5",
    )
    return HTMLResponse(
        render_doc_page(title=title, body_html=html, raw_path=raw_path)
    )


def render_markdown_file(
    *,
    title: str,
    path_str: str,
    label: str,
    raw_path: str,
    extensions: list[str],
    extension_configs: dict | None = None,
) -> HTMLResponse:
    return render_markdown_page(
        title=title,
        text=read_text_file(path_str, label),
        raw_path=raw_path,
        extensions=extensions,
        extension_configs=extension_configs,
    )
