# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""Shared in-process ASGI client for co-hosted API surfaces."""

from __future__ import annotations

import httpx


_client: httpx.AsyncClient | None = None


async def get_app_client() -> httpx.AsyncClient:
    """Return a lazily constructed in-process client for the FastAPI app."""

    global _client
    if _client is None:
        from app.main import app as fastapi_app

        _client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=fastapi_app),
            base_url="http://nurl.local",
            timeout=60.0,
        )
    return _client
