# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""OAuth compatibility stubs and transport shims for the mounted MCP app."""

from __future__ import annotations

import os
import secrets
import time
from urllib.parse import urlencode

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse, Response


router = APIRouter()

_OAUTH_PUBLIC_URL = os.environ.get("NURL_PUBLIC_URL", "").rstrip("/")


def _public_base_url(request: Request) -> str:
    if _OAUTH_PUBLIC_URL:
        return _OAUTH_PUBLIC_URL
    return str(request.base_url).rstrip("/")


@router.get("/.well-known/oauth-protected-resource", include_in_schema=False)
@router.get("/.well-known/oauth-protected-resource/mcp", include_in_schema=False)
def oauth_protected_resource_metadata(request: Request):
    base = _public_base_url(request)
    return JSONResponse({
        "resource": f"{base}/mcp",
        "authorization_servers": [base],
        "bearer_methods_supported": ["header"],
        "scopes_supported": [],
    })


@router.get("/.well-known/oauth-authorization-server", include_in_schema=False)
@router.get("/.well-known/openid-configuration", include_in_schema=False)
def oauth_auth_server_metadata(request: Request):
    base = _public_base_url(request)
    return JSONResponse({
        "issuer": base,
        "authorization_endpoint": f"{base}/authorize",
        "token_endpoint": f"{base}/token",
        "registration_endpoint": f"{base}/register",
        "response_types_supported": ["code"],
        "grant_types_supported": ["authorization_code", "client_credentials"],
        "token_endpoint_auth_methods_supported": ["none"],
        "code_challenge_methods_supported": ["S256", "plain"],
        "scopes_supported": [],
    })


@router.post("/register", include_in_schema=False)
async def oauth_register(request: Request):
    body: dict = {}
    try:
        body = await request.json()
    except Exception:
        pass
    print(f"[oauth/register] body={body!r}", flush=True)

    client_id = f"nurl-mcp-{secrets.token_urlsafe(8)}"
    response = {
        "client_id": client_id,
        "client_id_issued_at": int(time.time()),
        "grant_types": ["authorization_code"],
        "response_types": ["code"],
        "redirect_uris": [],
        "token_endpoint_auth_method": "none",
    }
    for key in (
        "redirect_uris", "grant_types", "response_types",
        "token_endpoint_auth_method", "client_name", "client_uri",
        "logo_uri", "scope", "contacts", "tos_uri", "policy_uri",
        "jwks_uri", "jwks", "software_id", "software_version",
        "software_statement", "application_type",
    ):
        if key in body:
            response[key] = body[key]
    return JSONResponse(response, status_code=201)


@router.get("/authorize", include_in_schema=False)
def oauth_authorize(
    request: Request,
    client_id: str | None = None,
    redirect_uri: str | None = None,
    state: str | None = None,
    code_challenge: str | None = None,
    code_challenge_method: str | None = None,
    response_type: str | None = None,
    scope: str | None = None,
):
    del request, client_id, code_challenge, code_challenge_method, response_type, scope
    if not redirect_uri:
        raise HTTPException(status_code=400, detail="redirect_uri required")
    params = {"code": secrets.token_urlsafe(16)}
    if state:
        params["state"] = state
    sep = "&" if "?" in redirect_uri else "?"
    return Response(status_code=302, headers={"Location": redirect_uri + sep + urlencode(params)})


@router.post("/token", include_in_schema=False)
async def oauth_token(request: Request):
    del request
    return JSONResponse({
        "access_token": secrets.token_urlsafe(32),
        "token_type": "Bearer",
        "expires_in": 60 * 60 * 24 * 365,
        "scope": "",
    })


async def mcp_client_compat_middleware(request: Request, call_next):
    path = request.scope.get("path", "")
    if path == "/mcp" or path.startswith("/mcp/"):
        if path == "/mcp":
            request.scope["path"] = "/mcp/"
            request.scope["raw_path"] = b"/mcp/"

        headers = list(request.scope.get("headers") or [])
        accept_val = ""
        for i, (key, value) in enumerate(headers):
            if key == b"accept":
                accept_val = value.decode("latin-1")
                headers.pop(i)
                break
        parts = [part.strip() for part in accept_val.split(",") if part.strip()]
        has_json = any(part.startswith("application/json") for part in parts)
        has_sse = any(part.startswith("text/event-stream") for part in parts)
        if not has_json:
            parts.append("application/json")
        if not has_sse:
            parts.append("text/event-stream")
        headers.append((b"accept", ", ".join(parts).encode("latin-1")))
        request.scope["headers"] = headers

    return await call_next(request)
