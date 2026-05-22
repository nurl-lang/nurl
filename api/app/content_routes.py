# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""Aggregate read-only content routers."""

from __future__ import annotations

from fastapi import APIRouter

from app.content_browser_routes import router as browser_router
from app.docs_routes import router as docs_router


router = APIRouter()
router.include_router(browser_router)
router.include_router(docs_router)
