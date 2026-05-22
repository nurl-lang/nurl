# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""Read-only documentation and MCP metadata routes."""

from __future__ import annotations

import os

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse, PlainTextResponse
from pydantic import BaseModel, Field

from app.docs_render import read_text_file, raw_text_response, render_markdown_file, render_markdown_page
from app.mcp_catalog import (
    NURL_GOTCHAS_PATH,
    NURL_GRAMMAR_PATH,
    NURL_README_PATH,
    NURL_ROADMAP_PATH,
    PROMPTS,
    RESOURCES,
    TOOLS,
)


router = APIRouter()

NURL_LICENSE_MIT_PATH = os.environ.get("NURL_LICENSE_MIT_PATH", "/opt/nurl/LICENSE-MIT")
NURL_LICENSE_APACHE_PATH = os.environ.get("NURL_LICENSE_APACHE_PATH", "/opt/nurl/LICENSE-APACHE")
NURL_NOTICE_PATH = os.environ.get("NURL_NOTICE_PATH", "/opt/nurl/NOTICE")
NURL_PUBLIC_URL = os.environ.get("NURL_PUBLIC_URL", "").rstrip("/")


class McpInfoResponse(BaseModel):
    url_path: str = Field(..., examples=["/mcp"])
    transport: str = Field(..., examples=["streamable-http"])
    tools: list[str]
    resources: list[str]
    prompts: list[str]
    client_config_example: dict = Field(
        ...,
        description=(
            "Drop-in snippet for mcp.json (Claude Desktop, Cursor, Windsurf, Zed). "
            "Replace the host/port to match your deployment."
        ),
    )

def _render_license_index(notice_text: str) -> HTMLResponse:
    md_text = (
        "# License\n\n"
        "NURL is **dual-licensed** under either of:\n\n"
        "- [MIT License](/license/mit) (also available [raw](/LICENSE-MIT))\n"
        "- [Apache License, Version 2.0](/license/apache) (also available [raw](/LICENSE-APACHE))\n\n"
        "at your option. SPDX identifier: `MIT OR Apache-2.0`.\n\n"
        "## NOTICE\n\n"
        "```\n" + notice_text.rstrip() + "\n```\n\n"
        "## Contribution\n\n"
        "Unless you explicitly state otherwise, any contribution intentionally "
        "submitted for inclusion in the work by you, as defined in the Apache-2.0 "
        "license, shall be dual-licensed as above, without any additional terms "
        "or conditions.\n"
    )
    return render_markdown_page(
        title="License",
        text=md_text,
        raw_path="/NOTICE",
        extensions=["fenced_code", "sane_lists"],
    )


@router.get(
    "/license",
    response_class=HTMLResponse,
    tags=["docs"],
    summary="Dual-license overview (MIT OR Apache-2.0)",
)
def license_index() -> HTMLResponse:
    try:
        notice_text = _read_text_file(NURL_NOTICE_PATH, "NOTICE")
    except HTTPException:
        notice_text = "NURL — Neural Unified Representation Language\nDual-licensed under MIT OR Apache-2.0.\n"
    return _render_license_index(notice_text)


@router.get("/license/mit", response_class=HTMLResponse, tags=["docs"], summary="Render LICENSE-MIT")
def license_mit_html() -> HTMLResponse:
    text = read_text_file(NURL_LICENSE_MIT_PATH, "LICENSE-MIT")
    return render_markdown_page(
        title="MIT License",
        text="# MIT License\n\n```\n" + text.rstrip() + "\n```\n",
        raw_path="/LICENSE-MIT",
        extensions=["fenced_code"],
    )


@router.get(
    "/license/apache",
    response_class=HTMLResponse,
    tags=["docs"],
    summary="Render LICENSE-APACHE (Apache 2.0)",
)
def license_apache_html() -> HTMLResponse:
    text = read_text_file(NURL_LICENSE_APACHE_PATH, "LICENSE-APACHE")
    return render_markdown_page(
        title="Apache License 2.0",
        text="# Apache License, Version 2.0\n\n```\n" + text.rstrip() + "\n```\n",
        raw_path="/LICENSE-APACHE",
        extensions=["fenced_code"],
    )


@router.get("/LICENSE-MIT", response_class=PlainTextResponse, tags=["docs"], summary="Raw LICENSE-MIT text")
def license_mit_raw() -> PlainTextResponse:
    return raw_text_response(NURL_LICENSE_MIT_PATH, "LICENSE-MIT")


@router.get("/LICENSE-APACHE", response_class=PlainTextResponse, tags=["docs"], summary="Raw LICENSE-APACHE text")
def license_apache_raw() -> PlainTextResponse:
    return raw_text_response(NURL_LICENSE_APACHE_PATH, "LICENSE-APACHE")


@router.get("/NOTICE", response_class=PlainTextResponse, tags=["docs"], summary="Raw NOTICE text")
def notice_raw() -> PlainTextResponse:
    return raw_text_response(NURL_NOTICE_PATH, "NOTICE")


@router.get("/readme", response_class=HTMLResponse, tags=["docs"], summary="Render README.md as HTML")
def readme_html() -> HTMLResponse:
    return render_markdown_file(
        title="README",
        path_str=NURL_README_PATH,
        label="README.md",
        raw_path="/readme.md",
        extensions=["fenced_code", "tables", "codehilite", "toc", "sane_lists"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
    )


@router.get("/readme.md", response_class=PlainTextResponse, tags=["docs"], summary="Raw README.md source")
def readme_raw() -> PlainTextResponse:
    return raw_text_response(NURL_README_PATH, "README.md")


@router.get("/roadmap", response_class=HTMLResponse, tags=["docs"], summary="Render ROADMAP.md as HTML")
def roadmap_html() -> HTMLResponse:
    return render_markdown_file(
        title="Roadmap",
        path_str=NURL_ROADMAP_PATH,
        label="ROADMAP.md",
        raw_path="/roadmap.md",
        extensions=["fenced_code", "tables", "codehilite", "toc", "sane_lists"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
    )


@router.get("/roadmap.md", response_class=PlainTextResponse, tags=["docs"], summary="Raw ROADMAP.md source")
def roadmap_raw() -> PlainTextResponse:
    return raw_text_response(NURL_ROADMAP_PATH, "ROADMAP.md")


@router.get("/gotchas", response_class=HTMLResponse, tags=["docs"], summary="Render docs/GOTCHAS.md as HTML")
def gotchas_html() -> HTMLResponse:
    return render_markdown_file(
        title="Gotchas",
        path_str=NURL_GOTCHAS_PATH,
        label="GOTCHAS.md",
        raw_path="/gotchas.md",
        extensions=["fenced_code", "codehilite"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
    )


@router.get("/gotchas.md", response_class=PlainTextResponse, tags=["docs"], summary="Raw docs/GOTCHAS.md source")
def gotchas_raw() -> PlainTextResponse:
    return raw_text_response(NURL_GOTCHAS_PATH, "GOTCHAS.md")


@router.get(
    "/grammar",
    response_class=HTMLResponse,
    tags=["docs"],
    summary="Render the current NURL grammar (spec/grammar.ebnf)",
)
def grammar_html() -> HTMLResponse:
    text = read_text_file(NURL_GRAMMAR_PATH, "grammar.ebnf")
    md_text = f"# Grammar (`spec/grammar.ebnf`)\n\n```ebnf\n{text}\n```\n"
    return render_markdown_page(
        title="Grammar",
        text=md_text,
        raw_path="/grammar.ebnf",
        extensions=["fenced_code", "codehilite"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
    )


@router.get("/grammar.ebnf", response_class=PlainTextResponse, tags=["docs"], summary="Raw grammar.ebnf source")
def grammar_raw() -> PlainTextResponse:
    return raw_text_response(NURL_GRAMMAR_PATH, "grammar.ebnf")


@router.get(
    "/mcp-info",
    response_model=McpInfoResponse,
    tags=["mcp"],
    summary="MCP server connection info",
    description=(
        "Describes the co-hosted Model Context Protocol server. "
        "The MCP JSON-RPC endpoint itself lives at `POST /mcp` (Streamable "
        "HTTP transport) but is implemented as an ASGI sub-app, so its "
        "methods are not enumerated in this OpenAPI schema."
    ),
)
def mcp_info(request: Request) -> McpInfoResponse:
    base = NURL_PUBLIC_URL or str(request.base_url).rstrip("/")
    return McpInfoResponse(
        url_path="/mcp",
        transport="streamable-http",
        tools=[tool.name for tool in TOOLS],
        resources=[resource.uri for resource in RESOURCES],
        prompts=[prompt.name for prompt in PROMPTS],
        client_config_example={
            "mcpServers": {
                "nurl": {
                    "url": base + "/mcp",
                    "transport": "streamable-http",
                }
            }
        },
    )
