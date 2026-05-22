# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""REST flavour of the NURL MCP server.

Mirrors the same surface as ``mcp_server.py`` (tools / resources / prompts)
but speaks plain HTTP — no JSON-RPC, no Streamable HTTP transport, no SSE.
LLM clients that can't (or won't) speak Streamable HTTP MCP can drive the
NURL toolchain through ordinary GET/POST calls.

The real MCP server at ``/mcp`` is unaffected. This module is mounted under
``/rmcp`` and re-uses the same in-process ASGI client trick that
``mcp_server.py`` uses to invoke ``/build*`` without a TCP round-trip.

Endpoints (mirror MCP's primitives):

  GET  /rmcp                          discovery + instructions + index
  GET  /rmcp/tools                    list of tools         (MCP `tools/list`)
  POST /rmcp/tools/{name}             call a tool           (MCP `tools/call`)
  GET  /rmcp/resources                list of resources     (MCP `resources/list`)
  GET  /rmcp/resources/read?uri=...   read a resource       (MCP `resources/read`)
  GET  /rmcp/prompts                  list of prompts       (MCP `prompts/list`)
  GET  /rmcp/prompts/{name}           get a prompt          (MCP `prompts/get`)

A single ``GET /rmcp`` returns instructions + the full catalog so a
language model can self-orient with one round-trip.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Request, status
from pydantic import BaseModel, Field
from app.mcp_catalog import (
    NURL_EXAMPLES_DIR,
    NURL_GOTCHAS_PATH,
    NURL_GRAMMAR_PATH,
    NURL_README_PATH,
    NURL_ROADMAP_PATH,
    NURL_STDLIB_DIR,
    NURL_TESTS_DIR,
    PROMPTS,
    PROMPT_SPECS,
    RESOURCES,
    REST_INSTRUCTIONS,
    TOOLS,
    PromptSpec,
    ResourceSpec,
    ToolSpec,
    render_nurl_coding_assistant_prompt,
)


router = APIRouter(prefix="/rmcp", tags=["rest-mcp"])


# ── In-process ASGI client (lazy) ──────────────────────────────────
#
# Lets tools call into the rest of the FastAPI app without a TCP round
# trip. Imported lazily to avoid an import cycle: ``app.main`` includes
# this router, so this module must not import from ``app.main`` at top level.

_client: httpx.AsyncClient | None = None


async def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        from app.main import app as fastapi_app  # local import breaks cycle
        _client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=fastapi_app),
            base_url="http://nurl.local",
            timeout=60.0,
        )
    return _client


# ── Catalog: tools / resources / prompts ──────────────────────────

INSTRUCTIONS = REST_INSTRUCTIONS


# ── Path-safety helper ────────────────────────────────────────────

def _safe_under(base_dir: str, name: str, *, label: str) -> Path:
    """Resolve `base_dir / name` and refuse anything outside `base_dir`.

    Mirrors the check pattern used by app.main and app.mcp_server so the
    REST-MCP can't be tricked into reading arbitrary files via path
    traversal in `name`.
    """
    base = Path(base_dir).resolve()
    target = (base / name).resolve()
    if base not in target.parents and target != base:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"refusing to read outside {label}: {name}",
        )
    if not target.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"{label} not found: {name}",
        )
    return target


# ── Tool handlers ─────────────────────────────────────────────────

async def _tool_build_native(args: dict[str, Any]) -> dict[str, Any]:
    client = await _get_client()
    r = await client.post("/build", json={
        "source":   args["source"],
        "filename": args.get("filename", "main.nu"),
    })
    r.raise_for_status()
    return r.json()


async def _tool_build_windows(args: dict[str, Any]) -> dict[str, Any]:
    client = await _get_client()
    r = await client.post("/build_windows", json={
        "source":   args["source"],
        "filename": args.get("filename", "main.nu"),
    })
    r.raise_for_status()
    return r.json()


async def _tool_build_macos(args: dict[str, Any]) -> dict[str, Any]:
    client = await _get_client()
    r = await client.post("/build_macos", json={
        "source":   args["source"],
        "filename": args.get("filename", "main.nu"),
    })
    r.raise_for_status()
    return r.json()


async def _tool_build_wasm(args: dict[str, Any]) -> dict[str, Any]:
    client = await _get_client()
    r = await client.post("/build_wasm", json={
        "source":        args["source"],
        "filename":      args.get("filename", "main.nu"),
        "return_format": "json",
        "emit_ll":       bool(args.get("emit_ll", False)),
    })
    r.raise_for_status()
    return r.json()


async def _tool_list_examples(_args: dict[str, Any]) -> list[dict[str, Any]]:
    client = await _get_client()
    r = await client.get("/examples")
    r.raise_for_status()
    return r.json()


async def _tool_read_example(args: dict[str, Any]) -> str:
    target = _safe_under(NURL_EXAMPLES_DIR, args["name"], label="example")
    if target.suffix != ".nu":
        raise HTTPException(status_code=400, detail="example must be a .nu file")
    return target.read_text("utf-8", errors="replace")


async def _tool_list_stdlib(_args: dict[str, Any]) -> list[str]:
    base = Path(NURL_STDLIB_DIR)
    if not base.is_dir():
        return []
    return sorted(
        p.relative_to(base).as_posix()
        for p in base.rglob("*.nu") if p.is_file()
    )


async def _tool_read_stdlib(args: dict[str, Any]) -> str:
    target = _safe_under(NURL_STDLIB_DIR, args["name"], label="stdlib")
    if target.suffix != ".nu":
        raise HTTPException(status_code=400, detail="stdlib module must be a .nu file")
    return target.read_text("utf-8", errors="replace")


async def _tool_list_tests(_args: dict[str, Any]) -> list[dict[str, Any]]:
    base = Path(NURL_TESTS_DIR)
    if not base.is_dir():
        return []
    out: list[dict[str, Any]] = []
    for p in sorted(base.rglob("*.nu")):
        if not p.is_file():
            continue
        rel = p.relative_to(base).as_posix()
        try:
            size = p.stat().st_size
        except OSError:
            continue
        out.append({"name": rel, "path": rel, "bytes": size})
    return out


async def _tool_read_test(args: dict[str, Any]) -> str:
    target = _safe_under(NURL_TESTS_DIR, args["name"], label="test")
    if target.suffix != ".nu":
        raise HTTPException(status_code=400, detail="test must be a .nu file")
    return target.read_text("utf-8", errors="replace")


async def _tool_read_grammar(_args: dict[str, Any]) -> str:
    p = Path(NURL_GRAMMAR_PATH)
    if not p.is_file():
        raise HTTPException(status_code=404, detail=f"grammar not found: {NURL_GRAMMAR_PATH}")
    return p.read_text("utf-8", errors="replace")


async def _tool_read_readme(_args: dict[str, Any]) -> str:
    p = Path(NURL_README_PATH)
    if not p.is_file():
        raise HTTPException(status_code=404, detail=f"README not found: {NURL_README_PATH}")
    return p.read_text("utf-8", errors="replace")


async def _tool_read_roadmap(_args: dict[str, Any]) -> str:
    p = Path(NURL_ROADMAP_PATH)
    if not p.is_file():
        raise HTTPException(status_code=404, detail=f"ROADMAP not found: {NURL_ROADMAP_PATH}")
    return p.read_text("utf-8", errors="replace")


async def _tool_read_gotchas(_args: dict[str, Any]) -> str:
    p = Path(NURL_GOTCHAS_PATH)
    if not p.is_file():
        raise HTTPException(status_code=404, detail=f"GOTCHAS not found: {NURL_GOTCHAS_PATH}")
    return p.read_text("utf-8", errors="replace")


_TOOL_HANDLERS = {
    "nurl_build_native":  _tool_build_native,
    "nurl_build_windows": _tool_build_windows,
    "nurl_build_macos":   _tool_build_macos,
    "nurl_build_wasm":    _tool_build_wasm,
    "nurl_list_examples": _tool_list_examples,
    "nurl_read_example":  _tool_read_example,
    "nurl_list_stdlib":   _tool_list_stdlib,
    "nurl_read_stdlib":   _tool_read_stdlib,
    "nurl_list_tests":    _tool_list_tests,
    "nurl_read_test":     _tool_read_test,
    "nurl_read_grammar":  _tool_read_grammar,
    "nurl_read_readme":   _tool_read_readme,
    "nurl_read_roadmap":  _tool_read_roadmap,
    "nurl_read_gotchas":  _tool_read_gotchas,
}


# ── Resource resolution ───────────────────────────────────────────
#
# Maps a `nurl://...` URI to (text, mime). 404 if unknown.

_RESOURCE_PREFIXES: list[tuple[str, str, str]] = [
    ("nurl://stdlib/",  NURL_STDLIB_DIR,   "stdlib"),
    ("nurl://example/", NURL_EXAMPLES_DIR, "example"),
    ("nurl://test/",    NURL_TESTS_DIR,    "test"),
]


def _read_resource(uri: str) -> tuple[str, str]:
    if uri == "nurl://grammar":
        p = Path(NURL_GRAMMAR_PATH)
        if not p.is_file():
            raise HTTPException(status_code=404, detail="grammar not found")
        return p.read_text("utf-8", errors="replace"), "text/plain"

    if uri == "nurl://readme":
        p = Path(NURL_README_PATH)
        if not p.is_file():
            raise HTTPException(status_code=404, detail="README not found")
        return p.read_text("utf-8", errors="replace"), "text/markdown"

    if uri == "nurl://roadmap":
        p = Path(NURL_ROADMAP_PATH)
        if not p.is_file():
            raise HTTPException(status_code=404, detail="ROADMAP not found")
        return p.read_text("utf-8", errors="replace"), "text/markdown"

    if uri == "nurl://gotchas":
        p = Path(NURL_GOTCHAS_PATH)
        if not p.is_file():
            raise HTTPException(status_code=404, detail="GOTCHAS not found")
        return p.read_text("utf-8", errors="replace"), "text/markdown"

    for prefix, base_dir, label in _RESOURCE_PREFIXES:
        if uri.startswith(prefix):
            rel = uri[len(prefix):]
            target = _safe_under(base_dir, rel, label=label)
            return target.read_text("utf-8", errors="replace"), "text/plain"

    raise HTTPException(status_code=404, detail=f"unknown resource uri: {uri}")


# ── Prompt renderers ──────────────────────────────────────────────

def _prompt_coding_assistant() -> str:
    return render_nurl_coding_assistant_prompt()


_PROMPT_RENDERERS = {
    "nurl_coding_assistant": _prompt_coding_assistant,
}


# ── Routes ─────────────────────────────────────────────────────────

class DiscoveryResponse(BaseModel):
    name:         str
    transport:    str
    instructions: str
    endpoints:    dict[str, str]
    tools:        list[ToolSpec]
    resources:    list[ResourceSpec]
    prompts:      list[PromptSpec]


@router.get(
    "",
    response_model=DiscoveryResponse,
    summary="REST-MCP discovery + index",
    description=(
        "All you need to drive the REST-MCP in one response: instructions, "
        "the endpoint map, and the catalog of tools, resources and prompts. "
        "An LLM client can `GET /rmcp` once and then operate from the "
        "returned schema."
    ),
)
def discovery() -> DiscoveryResponse:
    return DiscoveryResponse(
        name="nurl-rest-mcp",
        transport="rest",
        instructions=INSTRUCTIONS,
        endpoints={
            "tools_list":     "GET  /rmcp/tools",
            "tools_call":     "POST /rmcp/tools/{name}    (body = arguments object)",
            "resources_list": "GET  /rmcp/resources",
            "resources_read": "GET  /rmcp/resources/read?uri=<uri>",
            "prompts_list":   "GET  /rmcp/prompts",
            "prompts_get":    "GET  /rmcp/prompts/{name}",
        },
        tools=TOOLS,
        resources=RESOURCES,
        prompts=PROMPTS,
    )


@router.get("/tools", response_model=list[ToolSpec], summary="List tools")
def list_tools() -> list[ToolSpec]:
    return TOOLS


class ToolCallResponse(BaseModel):
    is_error: bool = False
    result:   Any  = None
    content:  list[dict[str, Any]] = Field(
        default_factory=list,
        description=(
            "Textual rendering of `result` mirroring MCP's "
            "`content: [{type:'text', text:...}]` shape."
        ),
    )


@router.post(
    "/tools/{name}",
    response_model=ToolCallResponse,
    summary="Call a tool",
    description=(
        "Invoke a named tool. The request body MUST be a JSON object "
        "matching the tool's `input_schema` (see GET /rmcp/tools). "
        "Empty body is accepted for tools that take no arguments."
    ),
)
async def call_tool(name: str, request: Request) -> ToolCallResponse:
    handler = _TOOL_HANDLERS.get(name)
    if handler is None:
        raise HTTPException(status_code=404, detail=f"unknown tool: {name}")

    raw = await request.body()
    if not raw.strip():
        args: dict[str, Any] = {}
    else:
        try:
            parsed = json.loads(raw)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=f"invalid JSON body: {e}")
        if not isinstance(parsed, dict):
            raise HTTPException(status_code=400, detail="body must be a JSON object")
        args = parsed

    try:
        result = await handler(args)
    except HTTPException:
        raise
    except KeyError as e:
        raise HTTPException(status_code=400, detail=f"missing argument: {e.args[0]}")
    except Exception as e:
        return ToolCallResponse(
            is_error=True,
            result={"error": str(e), "type": type(e).__name__},
            content=[{"type": "text", "text": f"error: {e}"}],
        )

    if isinstance(result, str):
        text = result
    else:
        text = json.dumps(result, indent=2, default=str)
    return ToolCallResponse(
        is_error=False,
        result=result,
        content=[{"type": "text", "text": text}],
    )


@router.get("/resources", response_model=list[ResourceSpec], summary="List resources")
def list_resources() -> list[ResourceSpec]:
    return RESOURCES


class ResourceReadResponse(BaseModel):
    uri:       str
    mime_type: str
    text:      str


@router.get(
    "/resources/read",
    response_model=ResourceReadResponse,
    summary="Read a resource",
    description=(
        "Resolve a `nurl://...` URI and return its text. URIs follow the "
        "templates listed in GET /rmcp/resources, e.g. "
        "`nurl://stdlib/core/option.nu`."
    ),
)
def read_resource(uri: str) -> ResourceReadResponse:
    text, mime = _read_resource(uri)
    return ResourceReadResponse(uri=uri, mime_type=mime, text=text)


@router.get("/prompts", response_model=list[PromptSpec], summary="List prompts")
def list_prompts() -> list[PromptSpec]:
    return PROMPTS


class PromptGetResponse(BaseModel):
    name:        str
    description: str
    messages:    list[dict[str, Any]]


@router.get(
    "/prompts/{name}",
    response_model=PromptGetResponse,
    summary="Get a prompt",
)
def get_prompt(name: str) -> PromptGetResponse:
    renderer = _PROMPT_RENDERERS.get(name)
    spec = PROMPT_SPECS.get(name)
    if renderer is None or spec is None:
        raise HTTPException(status_code=404, detail=f"unknown prompt: {name}")
    return PromptGetResponse(
        name=name,
        description=spec.description,
        messages=[{
            "role": "user",
            "content": [{"type": "text", "text": renderer()}],
        }],
    )
