# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""Read-only documentation and MCP metadata routes."""

from __future__ import annotations

import os
from dataclasses import dataclass

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


@dataclass(frozen=True)
class MarkdownDocSpec:
    page_path: str
    raw_path: str
    title: str
    source_path: str
    label: str
    page_summary: str
    raw_summary: str
    extensions: list[str]
    extension_configs: dict | None = None


@dataclass(frozen=True)
class InlineMarkdownDocSpec:
    page_path: str
    raw_path: str
    title: str
    source_path: str
    label: str
    page_summary: str
    raw_summary: str
    heading_md: str
    code_lang: str = ""
    extensions: list[str] | None = None
    extension_configs: dict | None = None


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


_MARKDOWN_DOC_SPECS: tuple[MarkdownDocSpec, ...] = (
    MarkdownDocSpec(
        page_path="/readme",
        raw_path="/readme.md",
        title="README",
        source_path=NURL_README_PATH,
        label="README.md",
        page_summary="Render README.md as HTML",
        raw_summary="Raw README.md source",
        extensions=["fenced_code", "tables", "codehilite", "toc", "sane_lists"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
    ),
    MarkdownDocSpec(
        page_path="/roadmap",
        raw_path="/roadmap.md",
        title="Roadmap",
        source_path=NURL_ROADMAP_PATH,
        label="ROADMAP.md",
        page_summary="Render ROADMAP.md as HTML",
        raw_summary="Raw ROADMAP.md source",
        extensions=["fenced_code", "tables", "codehilite", "toc", "sane_lists"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
    ),
    MarkdownDocSpec(
        page_path="/gotchas",
        raw_path="/gotchas.md",
        title="Gotchas",
        source_path=NURL_GOTCHAS_PATH,
        label="GOTCHAS.md",
        page_summary="Render docs/GOTCHAS.md as HTML",
        raw_summary="Raw docs/GOTCHAS.md source",
        extensions=["fenced_code", "codehilite"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
    ),
)

_INLINE_MARKDOWN_DOC_SPECS: tuple[InlineMarkdownDocSpec, ...] = (
    InlineMarkdownDocSpec(
        page_path="/license/mit",
        raw_path="/LICENSE-MIT",
        title="MIT License",
        source_path=NURL_LICENSE_MIT_PATH,
        label="LICENSE-MIT",
        page_summary="Render LICENSE-MIT",
        raw_summary="Raw LICENSE-MIT text",
        heading_md="# MIT License",
        extensions=["fenced_code"],
    ),
    InlineMarkdownDocSpec(
        page_path="/license/apache",
        raw_path="/LICENSE-APACHE",
        title="Apache License 2.0",
        source_path=NURL_LICENSE_APACHE_PATH,
        label="LICENSE-APACHE",
        page_summary="Render LICENSE-APACHE (Apache 2.0)",
        raw_summary="Raw LICENSE-APACHE text",
        heading_md="# Apache License, Version 2.0",
        extensions=["fenced_code"],
    ),
    InlineMarkdownDocSpec(
        page_path="/grammar",
        raw_path="/grammar.ebnf",
        title="Grammar",
        source_path=NURL_GRAMMAR_PATH,
        label="grammar.ebnf",
        page_summary="Render the current NURL grammar (spec/grammar.ebnf)",
        raw_summary="Raw grammar.ebnf source",
        heading_md="# Grammar (`spec/grammar.ebnf`)",
        code_lang="ebnf",
        extensions=["fenced_code", "codehilite"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
    ),
)


def _register_markdown_doc(spec: MarkdownDocSpec) -> None:
    def page_endpoint(spec: MarkdownDocSpec = spec) -> HTMLResponse:
        return render_markdown_file(
            title=spec.title,
            path_str=spec.source_path,
            label=spec.label,
            raw_path=spec.raw_path,
            extensions=spec.extensions,
            extension_configs=spec.extension_configs,
        )

    def raw_endpoint(spec: MarkdownDocSpec = spec) -> PlainTextResponse:
        return raw_text_response(spec.source_path, spec.label)

    router.add_api_route(
        spec.page_path,
        page_endpoint,
        response_class=HTMLResponse,
        tags=["docs"],
        summary=spec.page_summary,
    )
    router.add_api_route(
        spec.raw_path,
        raw_endpoint,
        response_class=PlainTextResponse,
        tags=["docs"],
        summary=spec.raw_summary,
    )


def _register_inline_markdown_doc(spec: InlineMarkdownDocSpec) -> None:
    def page_endpoint(spec: InlineMarkdownDocSpec = spec) -> HTMLResponse:
        source = read_text_file(spec.source_path, spec.label).rstrip()
        md_text = (
            f"{spec.heading_md}\n\n```{spec.code_lang}\n{source}\n```\n"
        )
        return render_markdown_page(
            title=spec.title,
            text=md_text,
            raw_path=spec.raw_path,
            extensions=spec.extensions or ["fenced_code"],
            extension_configs=spec.extension_configs,
        )

    def raw_endpoint(spec: InlineMarkdownDocSpec = spec) -> PlainTextResponse:
        return raw_text_response(spec.source_path, spec.label)

    router.add_api_route(
        spec.page_path,
        page_endpoint,
        response_class=HTMLResponse,
        tags=["docs"],
        summary=spec.page_summary,
    )
    router.add_api_route(
        spec.raw_path,
        raw_endpoint,
        response_class=PlainTextResponse,
        tags=["docs"],
        summary=spec.raw_summary,
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
        notice_text = read_text_file(NURL_NOTICE_PATH, "NOTICE")
    except HTTPException:
        notice_text = "NURL — Neural Unified Representation Language\nDual-licensed under MIT OR Apache-2.0.\n"
    return _render_license_index(notice_text)


@router.get("/NOTICE", response_class=PlainTextResponse, tags=["docs"], summary="Raw NOTICE text")
def notice_raw() -> PlainTextResponse:
    return raw_text_response(NURL_NOTICE_PATH, "NOTICE")


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


for _spec in _MARKDOWN_DOC_SPECS:
    _register_markdown_doc(_spec)

for _spec in _INLINE_MARKDOWN_DOC_SPECS:
    _register_inline_markdown_doc(_spec)
