# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""Read-only documentation and MCP metadata routes."""

from __future__ import annotations

import os
from pathlib import Path

import markdown as _md
from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import HTMLResponse, PlainTextResponse
from pydantic import BaseModel, Field

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


def _read_text_file(path_str: str, label: str) -> str:
    path = Path(path_str)
    if not path.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"{label} not found",
        )
    return path.read_text(encoding="utf-8", errors="replace")


_DOC_PAGE_TEMPLATE = """<!doctype html>
<html lang="en"><head>
<meta charset="utf-8" />
<title>{title} · NURL</title>
<meta name="viewport" content="width=device-width,initial-scale=1" />
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
<style>
  :root {{
    --bg:#0f1115; --panel:#161a21; --panel-2:#1b2029; --border:#262c38;
    --fg:#e6e8ee; --fg-dim:#9aa3b2; --accent:#7cc4ff;
  }}
  html,body {{ background:var(--bg); color:var(--fg); margin:0; }}
  body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, Roboto, sans-serif;
         line-height:1.6; }}
  .wrap {{ max-width: 860px; margin: 0 auto; padding: 2rem 1.25rem 4rem; }}
  header.doc-hdr {{ display:flex; align-items:center; gap:.75rem;
      padding:.75rem 1rem; border-bottom:1px solid var(--border);
      background:var(--panel); position:sticky; top:0; z-index:10; }}
  header.doc-hdr a {{ color:var(--accent); text-decoration:none; font-size:.9rem; }}
  header.doc-hdr a:hover {{ text-decoration:underline; }}
  header.doc-hdr .title {{ font-weight:600; }}
  header.doc-hdr .spacer {{ flex:1; }}
  h1,h2,h3,h4 {{ color:#fff; margin-top:2rem; }}
  h1 {{ border-bottom:1px solid var(--border); padding-bottom:.35em; }}
  h2 {{ border-bottom:1px solid var(--border); padding-bottom:.25em; }}
  a {{ color:var(--accent); }}
  code, pre {{ font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }}
  code {{ background:var(--panel-2); padding:.1em .35em; border-radius:4px;
         font-size:.92em; color:#e6e8ee; }}
  pre {{ background:var(--panel); border:1px solid var(--border);
        padding:.85rem 1rem; border-radius:8px; overflow:auto;
        font-size:.85rem; line-height:1.5; }}
  pre code {{ background:transparent; padding:0; }}
  blockquote {{ border-left:3px solid var(--border); margin:1em 0;
              padding:.25rem 1rem; color:var(--fg-dim); background:var(--panel); }}
  table {{ border-collapse:collapse; }}
  th, td {{ border:1px solid var(--border); padding:.4rem .75rem; }}
  th {{ background:var(--panel); }}
  hr {{ border:0; border-top:1px solid var(--border); margin:2rem 0; }}
  img {{ max-width:100%; }}
  ul, ol {{ padding-left: 1.5rem; }}
  .codehilite .c, .codehilite .c1, .codehilite .cm {{ color:#6A9955; font-style:italic; }}
  .codehilite .k, .codehilite .kd, .codehilite .kr {{ color:#C586C0; }}
  .codehilite .s, .codehilite .s1, .codehilite .s2, .codehilite .sb {{ color:#CE9178; }}
  .codehilite .mi, .codehilite .mf {{ color:#B5CEA8; }}
  .codehilite .nf {{ color:#DCDCAA; }}
  .codehilite .nc, .codehilite .nn {{ color:#4EC9B0; }}
  .codehilite .o {{ color:#D4D4D4; }}
</style>
</head><body>
<header class="doc-hdr">
  <a href="/">← Playground</a>
  <span class="title">{title}</span>
  <div class="spacer"></div>
  <a href="{raw_path}" target="_blank" rel="noopener">raw</a>
</header>
<div class="wrap">{content}</div>
</body></html>
"""


def _render_doc_page(*, title: str, body_html: str, raw_path: str) -> str:
    return _DOC_PAGE_TEMPLATE.format(title=title, content=body_html, raw_path=raw_path)


def _render_markdown_page(
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
    return HTMLResponse(_render_doc_page(title=title, body_html=html, raw_path=raw_path))


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
    return _render_markdown_page(
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
    text = _read_text_file(NURL_LICENSE_MIT_PATH, "LICENSE-MIT")
    return _render_markdown_page(
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
    text = _read_text_file(NURL_LICENSE_APACHE_PATH, "LICENSE-APACHE")
    return _render_markdown_page(
        title="Apache License 2.0",
        text="# Apache License, Version 2.0\n\n```\n" + text.rstrip() + "\n```\n",
        raw_path="/LICENSE-APACHE",
        extensions=["fenced_code"],
    )


@router.get("/LICENSE-MIT", response_class=PlainTextResponse, tags=["docs"], summary="Raw LICENSE-MIT text")
def license_mit_raw() -> PlainTextResponse:
    return PlainTextResponse(_read_text_file(NURL_LICENSE_MIT_PATH, "LICENSE-MIT"))


@router.get("/LICENSE-APACHE", response_class=PlainTextResponse, tags=["docs"], summary="Raw LICENSE-APACHE text")
def license_apache_raw() -> PlainTextResponse:
    return PlainTextResponse(_read_text_file(NURL_LICENSE_APACHE_PATH, "LICENSE-APACHE"))


@router.get("/NOTICE", response_class=PlainTextResponse, tags=["docs"], summary="Raw NOTICE text")
def notice_raw() -> PlainTextResponse:
    return PlainTextResponse(_read_text_file(NURL_NOTICE_PATH, "NOTICE"))


@router.get("/readme", response_class=HTMLResponse, tags=["docs"], summary="Render README.md as HTML")
def readme_html() -> HTMLResponse:
    text = _read_text_file(NURL_README_PATH, "README.md")
    return _render_markdown_page(
        title="README",
        text=text,
        raw_path="/readme.md",
        extensions=["fenced_code", "tables", "codehilite", "toc", "sane_lists"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
    )


@router.get("/readme.md", response_class=PlainTextResponse, tags=["docs"], summary="Raw README.md source")
def readme_raw() -> PlainTextResponse:
    return PlainTextResponse(_read_text_file(NURL_README_PATH, "README.md"))


@router.get("/roadmap", response_class=HTMLResponse, tags=["docs"], summary="Render ROADMAP.md as HTML")
def roadmap_html() -> HTMLResponse:
    text = _read_text_file(NURL_ROADMAP_PATH, "ROADMAP.md")
    return _render_markdown_page(
        title="Roadmap",
        text=text,
        raw_path="/roadmap.md",
        extensions=["fenced_code", "tables", "codehilite", "toc", "sane_lists"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
    )


@router.get("/roadmap.md", response_class=PlainTextResponse, tags=["docs"], summary="Raw ROADMAP.md source")
def roadmap_raw() -> PlainTextResponse:
    return PlainTextResponse(_read_text_file(NURL_ROADMAP_PATH, "ROADMAP.md"))


@router.get("/gotchas", response_class=HTMLResponse, tags=["docs"], summary="Render docs/GOTCHAS.md as HTML")
def gotchas_html() -> HTMLResponse:
    text = _read_text_file(NURL_GOTCHAS_PATH, "GOTCHAS.md")
    return _render_markdown_page(
        title="Gotchas",
        text=text,
        raw_path="/gotchas.md",
        extensions=["fenced_code", "codehilite"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
    )


@router.get("/gotchas.md", response_class=PlainTextResponse, tags=["docs"], summary="Raw docs/GOTCHAS.md source")
def gotchas_raw() -> PlainTextResponse:
    return PlainTextResponse(_read_text_file(NURL_GOTCHAS_PATH, "GOTCHAS.md"))


@router.get(
    "/grammar",
    response_class=HTMLResponse,
    tags=["docs"],
    summary="Render the current NURL grammar (spec/grammar.ebnf)",
)
def grammar_html() -> HTMLResponse:
    text = _read_text_file(NURL_GRAMMAR_PATH, "grammar.ebnf")
    md_text = f"# Grammar (`spec/grammar.ebnf`)\n\n```ebnf\n{text}\n```\n"
    return _render_markdown_page(
        title="Grammar",
        text=md_text,
        raw_path="/grammar.ebnf",
        extensions=["fenced_code", "codehilite"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
    )


@router.get("/grammar.ebnf", response_class=PlainTextResponse, tags=["docs"], summary="Raw grammar.ebnf source")
def grammar_raw() -> PlainTextResponse:
    return PlainTextResponse(_read_text_file(NURL_GRAMMAR_PATH, "grammar.ebnf"))


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
