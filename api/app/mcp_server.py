# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""Model Context Protocol server for the NURL compiler.

Exposes the same surface the HTTP API offers, but through MCP's
tool/resource/prompt abstractions so LLM clients (Claude Desktop,
Cursor, Windsurf, Zed, …) can drive NURL builds directly.

The MCP server is mounted under ``/mcp`` of the main FastAPI app by
``app.main``; clients connect via Streamable HTTP transport at
``http://<host>:8000/mcp``.

Implementation note: tools call back into the co-hosted FastAPI app
via an in-process ASGI transport (httpx.ASGITransport) so there is no
TCP round-trip and no port/host assumption. Resources read files
directly from disk.
"""
# NOTE: do NOT add `from __future__ import annotations` here — FastMCP's
# tool registration introspects parameter annotations at decoration time
# and calls `issubclass(annotation, Context)` on them. PEP 563 would
# stringify the annotations and crash with
# `TypeError: issubclass() arg 1 must be a class`.

from pathlib import Path

from mcp.server.fastmcp import FastMCP
from app.internal_http_client import get_app_client
from app.mcp_catalog import (
    MCP_INSTRUCTIONS,
    NURL_EXAMPLES_DIR,
    NURL_GOTCHAS_PATH,
    NURL_GRAMMAR_PATH,
    NURL_README_PATH,
    NURL_ROADMAP_PATH,
    NURL_STDLIB_DIR,
    NURL_TESTS_DIR,
    PROMPT_SPECS,
    RESOURCE_SPECS,
    TOOL_SPECS,
    render_nurl_coding_assistant_prompt,
)


mcp = FastMCP(
    name="nurl",
    # Keep FastMCP's Streamable HTTP endpoint at `/mcp` inside its own
    # app, and mount that app at `/` in app.main. This avoids Starlette's
    # `Mount("/mcp", …)` behaviour of redirecting `/mcp` → `/mcp/` with
    # HTTP 307, which loses the POST body and breaks MCP clients.
    streamable_http_path="/mcp",
    instructions=MCP_INSTRUCTIONS,
)

# ── Tools ──────────────────────────────────────────────────────────

@mcp.tool(
    description=TOOL_SPECS["nurl_build_native"].description,
)
async def nurl_build_native(source: str, filename: str = "main.nu") -> dict:
    client = await get_app_client()
    r = await client.post("/build", json={"source": source, "filename": filename})
    r.raise_for_status()
    return r.json()


@mcp.tool(
    description=TOOL_SPECS["nurl_build_windows"].description,
)
async def nurl_build_windows(source: str, filename: str = "main.nu") -> dict:
    client = await get_app_client()
    r = await client.post("/build_windows", json={"source": source, "filename": filename})
    r.raise_for_status()
    return r.json()


@mcp.tool(
    description=TOOL_SPECS["nurl_build_macos"].description,
)
async def nurl_build_macos(source: str, filename: str = "main.nu") -> dict:
    client = await get_app_client()
    r = await client.post("/build_macos", json={"source": source, "filename": filename})
    r.raise_for_status()
    return r.json()


@mcp.tool(
    description=TOOL_SPECS["nurl_build_wasm"].description,
)
async def nurl_build_wasm(
    source: str,
    filename: str = "main.nu",
    emit_ll: bool = False,
) -> dict:
    client = await get_app_client()
    r = await client.post(
        "/build_wasm",
        json={
            "source": source,
            "filename": filename,
            "return_format": "json",
            "emit_ll": emit_ll,
        },
    )
    r.raise_for_status()
    return r.json()


@mcp.tool(
    description=TOOL_SPECS["nurl_list_examples"].description,
)
async def nurl_list_examples() -> list:
    client = await get_app_client()
    r = await client.get("/examples")
    r.raise_for_status()
    return r.json()


@mcp.tool(
    description=TOOL_SPECS["nurl_read_example"].description,
)
async def nurl_read_example(name: str) -> str:
    client = await get_app_client()
    r = await client.get(f"/examples/{name}")
    r.raise_for_status()
    return r.json()["source"]


@mcp.tool(
    description=TOOL_SPECS["nurl_list_stdlib"].description,
)
async def nurl_list_stdlib() -> list:
    base = Path(NURL_STDLIB_DIR)
    if not base.is_dir():
        return []
    return sorted(
        str(p.relative_to(base)) for p in base.rglob("*.nu") if p.is_file()
    )


@mcp.tool(
    description=TOOL_SPECS["nurl_read_stdlib"].description,
)
async def nurl_read_stdlib(name: str) -> str:
    base = Path(NURL_STDLIB_DIR).resolve()
    target = (base / name).resolve()
    if base not in target.parents and target != base:
        raise ValueError(f"refusing to read outside stdlib: {name}")
    if not target.is_file() or target.suffix != ".nu":
        raise FileNotFoundError(f"stdlib module not found: {name}")
    return target.read_text("utf-8")


@mcp.tool(
    description=TOOL_SPECS["nurl_list_tests"].description,
)
async def nurl_list_tests() -> list:
    base = Path(NURL_TESTS_DIR)
    if not base.is_dir():
        return []
    out: list[dict] = []
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


@mcp.tool(
    description=TOOL_SPECS["nurl_read_test"].description,
)
async def nurl_read_test(name: str) -> str:
    base = Path(NURL_TESTS_DIR).resolve()
    target = (base / name).resolve()
    if base not in target.parents and target != base:
        raise ValueError(f"refusing to read outside tests: {name}")
    if not target.is_file() or target.suffix != ".nu":
        raise FileNotFoundError(f"test not found: {name}")
    return target.read_text("utf-8")


@mcp.tool(
    description=TOOL_SPECS["nurl_read_grammar"].description,
)
async def nurl_read_grammar() -> str:
    p = Path(NURL_GRAMMAR_PATH)
    if not p.is_file():
        raise FileNotFoundError(f"grammar not found: {NURL_GRAMMAR_PATH}")
    return p.read_text("utf-8")


@mcp.tool(
    description=TOOL_SPECS["nurl_read_readme"].description,
)
async def nurl_read_readme() -> str:
    p = Path(NURL_README_PATH)
    if not p.is_file():
        raise FileNotFoundError(f"README not found: {NURL_README_PATH}")
    return p.read_text("utf-8")


@mcp.tool(
    description=TOOL_SPECS["nurl_read_roadmap"].description,
)
async def nurl_read_roadmap() -> str:
    p = Path(NURL_ROADMAP_PATH)
    if not p.is_file():
        raise FileNotFoundError(f"ROADMAP not found: {NURL_ROADMAP_PATH}")
    return p.read_text("utf-8")


@mcp.tool(
    description=TOOL_SPECS["nurl_read_gotchas"].description,
)
async def nurl_read_gotchas() -> str:
    p = Path(NURL_GOTCHAS_PATH)
    if not p.is_file():
        raise FileNotFoundError(f"GOTCHAS not found: {NURL_GOTCHAS_PATH}")
    return p.read_text("utf-8")


# ── Resources ──────────────────────────────────────────────────────

@mcp.resource(
    "nurl://grammar",
    name=RESOURCE_SPECS["nurl://grammar"].name,
    description=RESOURCE_SPECS["nurl://grammar"].description,
    mime_type=RESOURCE_SPECS["nurl://grammar"].mime_type,
)
def resource_grammar() -> str:
    p = Path(NURL_GRAMMAR_PATH)
    return p.read_text("utf-8") if p.is_file() else "(grammar file not found)"


@mcp.resource(
    "nurl://readme",
    name=RESOURCE_SPECS["nurl://readme"].name,
    description=RESOURCE_SPECS["nurl://readme"].description,
    mime_type=RESOURCE_SPECS["nurl://readme"].mime_type,
)
def resource_readme() -> str:
    p = Path(NURL_README_PATH)
    return p.read_text("utf-8") if p.is_file() else "(README not found)"


@mcp.resource(
    "nurl://roadmap",
    name=RESOURCE_SPECS["nurl://roadmap"].name,
    description=RESOURCE_SPECS["nurl://roadmap"].description,
    mime_type=RESOURCE_SPECS["nurl://roadmap"].mime_type,
)
def resource_roadmap() -> str:
    p = Path(NURL_ROADMAP_PATH)
    return p.read_text("utf-8") if p.is_file() else "(ROADMAP not found)"


@mcp.resource(
    "nurl://gotchas",
    name=RESOURCE_SPECS["nurl://gotchas"].name,
    description=RESOURCE_SPECS["nurl://gotchas"].description,
    mime_type=RESOURCE_SPECS["nurl://gotchas"].mime_type,
)
def resource_gotchas() -> str:
    p = Path(NURL_GOTCHAS_PATH)
    return p.read_text("utf-8") if p.is_file() else "(GOTCHAS not found)"


@mcp.resource(
    "nurl://stdlib/{path}",
    name=RESOURCE_SPECS["nurl://stdlib/{path}"].name,
    description=RESOURCE_SPECS["nurl://stdlib/{path}"].description,
    mime_type=RESOURCE_SPECS["nurl://stdlib/{path}"].mime_type,
)
def resource_stdlib(path: str) -> str:
    base = Path(NURL_STDLIB_DIR).resolve()
    target = (base / path).resolve()
    # Refuse path traversal outside the stdlib tree.
    if base not in target.parents and target != base:
        raise ValueError(f"refusing to read outside stdlib: {path}")
    if not target.is_file():
        raise FileNotFoundError(f"stdlib module not found: {path}")
    return target.read_text("utf-8")


@mcp.resource(
    "nurl://example/{name}",
    name=RESOURCE_SPECS["nurl://example/{name}"].name,
    description=RESOURCE_SPECS["nurl://example/{name}"].description,
    mime_type=RESOURCE_SPECS["nurl://example/{name}"].mime_type,
)
def resource_example(name: str) -> str:
    base = Path(NURL_EXAMPLES_DIR).resolve()
    target = (base / name).resolve()
    if base not in target.parents and target != base:
        raise ValueError(f"refusing to read outside examples: {name}")
    if not target.is_file():
        raise FileNotFoundError(f"example not found: {name}")
    return target.read_text("utf-8")


@mcp.resource(
    "nurl://test/{name}",
    name=RESOURCE_SPECS["nurl://test/{name}"].name,
    description=RESOURCE_SPECS["nurl://test/{name}"].description,
    mime_type=RESOURCE_SPECS["nurl://test/{name}"].mime_type,
)
def resource_test(name: str) -> str:
    base = Path(NURL_TESTS_DIR).resolve()
    target = (base / name).resolve()
    if base not in target.parents and target != base:
        raise ValueError(f"refusing to read outside tests: {name}")
    if not target.is_file():
        raise FileNotFoundError(f"test not found: {name}")
    return target.read_text("utf-8")


# ── Prompts ────────────────────────────────────────────────────────

@mcp.prompt(
    name="nurl_coding_assistant",
    description=PROMPT_SPECS["nurl_coding_assistant"].description,
)
def prompt_coding_assistant() -> str:
    return render_nurl_coding_assistant_prompt()
