# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""Build artifact registration, download-token lifecycle, and cleanup."""

from __future__ import annotations

import os
import secrets
import threading
import time
from pathlib import Path

from fastapi import Request
from pydantic import BaseModel


class BuildArtifact(BaseModel):
    name: str
    bytes: int
    download_url: str
    token: str


class DownloadEntry:
    __slots__ = ("path", "filename", "media_type", "expires_at")

    def __init__(self, path: Path, filename: str, media_type: str, expires_at: float) -> None:
        self.path = path
        self.filename = filename
        self.media_type = media_type
        self.expires_at = expires_at


def sanitize_basename(raw: str | None) -> str:
    if not raw:
        return "main"
    stem = Path(raw).stem
    cleaned = "".join(c for c in stem if c.isalnum() or c in "._-")
    return cleaned or "main"


class ArtifactStore:
    def __init__(self, output_dir: str, ttl_sec: int) -> None:
        self.output_dir = Path(output_dir).resolve()
        self.ttl_sec = ttl_sec
        self._registry: dict[str, DownloadEntry] = {}
        self._lock = threading.Lock()

    def gc(self, now: float | None = None) -> None:
        now = now if now is not None else time.time()
        with self._lock:
            expired = [token for token, entry in self._registry.items() if entry.expires_at <= now]
            for token in expired:
                entry = self._registry.pop(token, None)
                if entry is None:
                    continue
                try:
                    if entry.path.is_file():
                        entry.path.unlink()
                    parent = entry.path.parent
                    if parent.is_dir() and parent.parent == self.output_dir:
                        try:
                            next(parent.iterdir())
                        except StopIteration:
                            parent.rmdir()
                except OSError:
                    pass

    def get(self, token: str) -> DownloadEntry | None:
        with self._lock:
            return self._registry.get(token)

    def register_build_artifact(
        self,
        path: Path,
        media_type: str,
        request: Request,
        *,
        executable: bool = False,
    ) -> BuildArtifact | None:
        if not path.is_file():
            return None
        if executable:
            try:
                path.chmod(0o755)
            except OSError:
                pass
        token = self._register_download(path, media_type)
        return BuildArtifact(
            name=path.name,
            bytes=path.stat().st_size,
            download_url=self._download_url(request, token),
            token=token,
        )

    def _register_download(self, path: Path, media_type: str) -> str:
        token = secrets.token_urlsafe(24)
        entry = DownloadEntry(
            path=path,
            filename=path.name,
            media_type=media_type,
            expires_at=time.time() + self.ttl_sec,
        )
        with self._lock:
            self._registry[token] = entry
        return token

    def _download_url(self, request: Request | None, token: str) -> str:
        path = f"/download/{token}"
        public = os.environ.get("NURL_PUBLIC_URL", "").rstrip("/")
        if public:
            return f"{public}{path}"
        if request is None:
            return path
        return str(request.url_for("download_artifact", token=token))
