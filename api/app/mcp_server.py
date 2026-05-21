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

import os
from pathlib import Path

import httpx
from mcp.server.fastmcp import FastMCP

# Paths mirror those in app.main so that both the HTTP API and the MCP
# server surface identical content.
NURL_STDLIB_DIR   = os.environ.get("NURL_STDLIB_DIR",   "/opt/nurl/stdlib")
NURL_EXAMPLES_DIR = os.environ.get("NURL_EXAMPLES_DIR", "/opt/nurl/examples")
NURL_TESTS_DIR    = os.environ.get("NURL_TESTS_DIR",    "/opt/nurl/compiler/tests")
NURL_GRAMMAR_PATH = os.environ.get("NURL_GRAMMAR_PATH", "/opt/nurl/spec/grammar.ebnf")
NURL_README_PATH  = os.environ.get("NURL_README_PATH",  "/opt/nurl/README.md")
NURL_ROADMAP_PATH = os.environ.get("NURL_ROADMAP_PATH", "/opt/nurl/ROADMAP.md")
NURL_GOTCHAS_PATH = os.environ.get("NURL_GOTCHAS_PATH", "/opt/nurl/docs/GOTCHAS.md")


mcp = FastMCP(
    name="nurl",
    # Keep FastMCP's Streamable HTTP endpoint at `/mcp` inside its own
    # app, and mount that app at `/` in app.main. This avoids Starlette's
    # `Mount("/mcp", …)` behaviour of redirecting `/mcp` → `/mcp/` with
    # HTTP 307, which loses the POST body and breaks MCP clients.
    streamable_http_path="/mcp",
    instructions=(
        "NURL language toolchain. Use `nurl_build_native` (Linux ELF), "
        "`nurl_build_windows` (Windows .exe via zig cc), "
        "`nurl_build_macos` (macOS Mach-O via zig cc), or "
        "`nurl_build_wasm` (wasm32-wasi via zig cc) to compile source. The language uses a "
        "terse prefix notation: functions are declared with "
        "`@ name → ret_ty { body }`, return via `^ expr`, and call "
        "functions with parenthesised prefix form like `( puts `hello` )`. "
        "Read `nurl://grammar` and `nurl://readme` for the full spec; "
        "fetch working examples via `nurl_read_example`."
    ),
)


# ── Internal HTTP client (in-process ASGI, no real socket) ─────────
#
# The app is imported lazily inside get_client() to avoid a circular
# import at module load time: app.main imports this module to mount
# the MCP sub-app.

_client = None  # type: httpx.AsyncClient | None


async def _get_client():
    global _client
    if _client is None:
        from app.main import app as fastapi_app  # local import, breaks cycle
        _client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=fastapi_app),
            base_url="http://nurl.local",
            timeout=60.0,
        )
    return _client


# ── Tools ──────────────────────────────────────────────────────────

@mcp.tool(
    description=(
        "Compile NURL source to a native x86_64 Linux ELF binary. "
        "Returns build status, nurlc+clang return codes and stderr, "
        "plus download URLs for the generated `.ll` (LLVM IR) and "
        "the binary. Equivalent to `POST /build`."
    ),
)
async def nurl_build_native(source: str, filename: str = "main.nu") -> dict:
    client = await _get_client()
    r = await client.post("/build", json={"source": source, "filename": filename})
    r.raise_for_status()
    return r.json()


@mcp.tool(
    description=(
        "Cross-compile NURL source to a Windows x86_64 .exe via zig cc "
        "(x86_64-windows-gnu). Returns build status, nurlc + zig cc return "
        "codes and stderr, plus download URLs for the generated `.ll` (LLVM "
        "IR) and the `.exe`. canvas/audio FFI is not supported on this "
        "target. Equivalent to `POST /build_windows`."
    ),
)
async def nurl_build_windows(source: str, filename: str = "main.nu") -> dict:
    client = await _get_client()
    r = await client.post("/build_windows", json={"source": source, "filename": filename})
    r.raise_for_status()
    return r.json()


@mcp.tool(
    description=(
        "Cross-compile NURL source to a macOS x86_64 Mach-O binary via zig cc. "
        "Returns build status, nurlc+zig return codes and stderr, plus download "
        "URLs for the generated `.ll` (LLVM IR) and the binary. The result "
        "links only libSystem — canvas/audio FFI and libcurl-backed HTTP are "
        "not supported on this target. The binary is unsigned; users must "
        "clear the Gatekeeper quarantine attribute before running it. "
        "Equivalent to `POST /build_macos`."
    ),
)
async def nurl_build_macos(source: str, filename: str = "main.nu") -> dict:
    client = await _get_client()
    r = await client.post("/build_macos", json={"source": source, "filename": filename})
    r.raise_for_status()
    return r.json()


@mcp.tool(
    description=(
        "Compile NURL source to a wasm32-wasi WebAssembly module. "
        "Returns the wasm bytes (base64) plus compile logs. Suitable "
        "for running in-browser via a WASI shim or with wasmtime. "
        "Equivalent to `POST /build_wasm`."
    ),
)
async def nurl_build_wasm(
    source: str,
    filename: str = "main.nu",
    emit_ll: bool = False,
) -> dict:
    client = await _get_client()
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
    description=(
        "List bundled NURL example programs. Each entry has `name`, "
        "`path` and `bytes`. Use `nurl_read_example` to fetch the "
        "source of a specific one."
    ),
)
async def nurl_list_examples() -> list:
    client = await _get_client()
    r = await client.get("/examples")
    r.raise_for_status()
    return r.json()


@mcp.tool(
    description=(
        "Read the source of a bundled NURL example by name "
        "(e.g. 'enigma.nu' or 'calculator.nu'). Returns the full "
        "source as a string."
    ),
)
async def nurl_read_example(name: str) -> str:
    client = await _get_client()
    r = await client.get(f"/examples/{name}")
    r.raise_for_status()
    return r.json()["source"]


@mcp.tool(
    description=(
        "List NURL stdlib modules (.nu files under the stdlib "
        "directory). Return relative paths; read any one via the "
        "`nurl://stdlib/{path}` resource."
    ),
)
async def nurl_list_stdlib() -> list:
    base = Path(NURL_STDLIB_DIR)
    if not base.is_dir():
        return []
    return sorted(
        str(p.relative_to(base)) for p in base.rglob("*.nu") if p.is_file()
    )


@mcp.tool(
    description=(
        "Read the source of a NURL stdlib module by relative path "
        "(e.g. 'core/option.nu' or 'std/string.nu'). Returns the full "
        "source as a string."
    ),
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
    description=(
        "List bundled NURL compiler test programs (.nu files under "
        "compiler/tests). Compiler has passed all of them. Each entry has `name`, `path` and `bytes`. "
        "Use `nurl_read_test` to fetch the source of a specific one."
    ),
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
    description=(
        "Read the source of a bundled NURL compiler test by name "
        "(e.g. 'generic_struct.nu' or 'string_mvp3.nu'). Returns the "
        "full source as a string."
    ),
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
    description=(
        "Read the authoritative NURL grammar (EBNF) from "
        "`spec/grammar.ebnf`. Equivalent to the `nurl://grammar` resource, "
        "exposed as a tool for clients that don't fetch resources."
    ),
)
async def nurl_read_grammar() -> str:
    p = Path(NURL_GRAMMAR_PATH)
    if not p.is_file():
        raise FileNotFoundError(f"grammar not found: {NURL_GRAMMAR_PATH}")
    return p.read_text("utf-8")


@mcp.tool(
    description=(
        "Read the project README (`README.md`) covering NURL design, "
        "usage and toolchain. Equivalent to the `nurl://readme` resource."
    ),
)
async def nurl_read_readme() -> str:
    p = Path(NURL_README_PATH)
    if not p.is_file():
        raise FileNotFoundError(f"README not found: {NURL_README_PATH}")
    return p.read_text("utf-8")


@mcp.tool(
    description=(
        "Read the project ROADMAP (`ROADMAP.md`) covering planned features "
        "and direction. Equivalent to the `nurl://roadmap` resource."
    ),
)
async def nurl_read_roadmap() -> str:
    p = Path(NURL_ROADMAP_PATH)
    if not p.is_file():
        raise FileNotFoundError(f"ROADMAP not found: {NURL_ROADMAP_PATH}")
    return p.read_text("utf-8")


@mcp.tool(
    description=(
        "Read the NURL gotchas / pitfalls guide (`docs/GOTCHAS.md`) "
        "documenting common mistakes and surprising behaviour. "
        "Equivalent to the `nurl://gotchas` resource."
    ),
)
async def nurl_read_gotchas() -> str:
    p = Path(NURL_GOTCHAS_PATH)
    if not p.is_file():
        raise FileNotFoundError(f"GOTCHAS not found: {NURL_GOTCHAS_PATH}")
    return p.read_text("utf-8")


# ── Resources ──────────────────────────────────────────────────────

@mcp.resource(
    "nurl://grammar",
    name="NURL grammar (EBNF)",
    description="The authoritative EBNF grammar for the current NURL version.",
    mime_type="text/plain",
)
def resource_grammar() -> str:
    p = Path(NURL_GRAMMAR_PATH)
    return p.read_text("utf-8") if p.is_file() else "(grammar file not found)"


@mcp.resource(
    "nurl://readme",
    name="NURL README",
    description="Project README covering design, usage and toolchain. Use this to get general information about NURL. This is BIG. Use only when needed.",
    mime_type="text/markdown",
)
def resource_readme() -> str:
    p = Path(NURL_README_PATH)
    return p.read_text("utf-8") if p.is_file() else "(README not found)"


@mcp.resource(
    "nurl://roadmap",
    name="NURL ROADMAP",
    description="Project ROADMAP covering planned features and direction.",
    mime_type="text/markdown",
)
def resource_roadmap() -> str:
    p = Path(NURL_ROADMAP_PATH)
    return p.read_text("utf-8") if p.is_file() else "(ROADMAP not found)"


@mcp.resource(
    "nurl://gotchas",
    name="NURL gotchas",
    description="Common pitfalls and surprising behaviour when writing NURL. Read this before debugging tricky compile or runtime errors.",
    mime_type="text/markdown",
)
def resource_gotchas() -> str:
    p = Path(NURL_GOTCHAS_PATH)
    return p.read_text("utf-8") if p.is_file() else "(GOTCHAS not found)"


@mcp.resource(
    "nurl://stdlib/{path}",
    name="NURL stdlib module",
    description="Source of a stdlib .nu module, e.g. 'core/option.nu'.",
    mime_type="text/plain",
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
    name="NURL example program",
    description="Source of a bundled example, e.g. 'calculator.nu'.",
    mime_type="text/plain",
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
    name="NURL compiler test",
    description="Source of a bundled compiler test, e.g. 'generic_struct.nu'.",
    mime_type="text/plain",
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
    description=(
        "Prime the assistant with NURL's syntax and conventions before "
        "asking it to write or review NURL code."
    ),
)
def prompt_coding_assistant() -> str:
    # Kept compact on purpose: full grammar + one canonical example is
    # enough to ground most small-to-medium LLMs.
    example = ""
    p = Path(NURL_EXAMPLES_DIR) / "calculator.nu"
    if p.is_file():
        example = p.read_text("utf-8")
    return (
        "You are helping a developer write NURL code.\n\n"
        "Key syntax reminders:\n"
        "  - Function: `@ name → ret_ty { body }` (not `fn name() -> ret_ty`)\n"
        "  - Return:   `^ expr`\n"
        "  - Call:     `( fname arg1 arg2 )` (parenthesised prefix)\n"
        "  - String:   backticks: `` `hello` ``\n"
        "  - Types:    `i` (i64), `u` (u64), `f` (f64), `b` (bool), "
        "`s` (string), `v` (void), `* T` (pointer to T)\n"
        "  - Imports:  ``$ `stdlib/core/option.nu` ``\n"
        "  - FFI:      ``& `libc` @ puts * i8 → i``\n\n"
        "Before writing, you MAY call the `nurl_read_example` tool or "
        "read the `nurl://grammar` resource to double-check syntax. "
        "Always validate generated code by calling `nurl_build_native` "
        "and inspecting stderr; fix errors and retry.\n\n"
        "Reference example (calculator.nu):\n"
        "```\n" + example + "\n```"
    )
