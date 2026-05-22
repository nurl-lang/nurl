# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""Read-only content routes for examples, stdlib, docs, and MCP metadata."""

from __future__ import annotations

import os
from pathlib import Path

import markdown as _md
from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import HTMLResponse, PlainTextResponse
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
    RESOURCES,
    TOOLS,
)


router = APIRouter()

NURL_LICENSE_MIT_PATH = os.environ.get("NURL_LICENSE_MIT_PATH", "/opt/nurl/LICENSE-MIT")
NURL_LICENSE_APACHE_PATH = os.environ.get("NURL_LICENSE_APACHE_PATH", "/opt/nurl/LICENSE-APACHE")
NURL_NOTICE_PATH = os.environ.get("NURL_NOTICE_PATH", "/opt/nurl/NOTICE")
NURL_PUBLIC_URL = os.environ.get("NURL_PUBLIC_URL", "").rstrip("/")


class ExampleInfo(BaseModel):
    name: str
    path: str
    bytes: int


class ExampleContent(BaseModel):
    name: str
    source: str
    bytes: int


class TestInfo(BaseModel):
    name: str
    path: str
    bytes: int


class TestContent(BaseModel):
    name: str
    source: str
    bytes: int


class StdlibInfo(BaseModel):
    name: str
    path: str
    bytes: int


class StdlibContent(BaseModel):
    name: str
    source: str
    bytes: int


class McpInfoResponse(BaseModel):
    url_path: str = Field(..., examples=["/mcp"])
    transport: str = Field(..., examples=["streamable-http"])
    tools: list[str]
    resources: list[str]
    prompts: list[str]
    client_config_example: dict = Field(
        ...,
        description="Drop-in snippet for mcp.json (Claude Desktop, Cursor, Windsurf, Zed). Replace the host/port to match your deployment.",
    )


def _list_nu_files(root_dir: str) -> list[dict]:
    root = Path(root_dir)
    if not root.is_dir():
        return []
    out: list[dict] = []
    for path in sorted(root.rglob("*.nu")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        try:
            size = path.stat().st_size
        except OSError:
            continue
        out.append({"name": rel, "path": rel, "bytes": size})
    return out


def _safe_under(base_dir: str, name: str, *, label: str) -> Path:
    root = Path(base_dir).resolve()
    target = (root / name).resolve()
    if root not in target.parents and target != root:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"invalid {label} path")
    if not target.is_file() or target.suffix != ".nu":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"{label} not found")
    return target


def _read_text_file(path_str: str, label: str) -> str:
    path = Path(path_str)
    if not path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"{label} not found")
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


@router.get("/examples", response_model=list[ExampleInfo], tags=["examples"])
def list_examples() -> list[ExampleInfo]:
    return [ExampleInfo(**entry) for entry in _list_nu_files(NURL_EXAMPLES_DIR)]


@router.get("/examples/{name:path}", response_model=ExampleContent, tags=["examples"])
def get_example(name: str) -> ExampleContent:
    target = _safe_under(NURL_EXAMPLES_DIR, name, label="example")
    source = target.read_text(encoding="utf-8", errors="replace")
    return ExampleContent(name=name, source=source, bytes=len(source.encode("utf-8")))


@router.get("/tests", response_model=list[TestInfo], tags=["tests"])
def list_tests() -> list[TestInfo]:
    return [TestInfo(**entry) for entry in _list_nu_files(NURL_TESTS_DIR)]


@router.get("/tests/{name:path}", response_model=TestContent, tags=["tests"])
def get_test(name: str) -> TestContent:
    target = _safe_under(NURL_TESTS_DIR, name, label="test")
    source = target.read_text(encoding="utf-8", errors="replace")
    return TestContent(name=name, source=source, bytes=len(source.encode("utf-8")))


_STDLIB_VIEWER_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
<title>NURL Stdlib · Browser</title>
<style>
  :root {
    --bg: #0f1115;
    --panel: #161a21;
    --panel-2: #1d222b;
    --border: #262c38;
    --fg: #e6e8ee;
    --fg-dim: #9aa3b2;
    --accent: #7cc4ff;
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; margin: 0; }
  body {
    background: var(--bg); color: var(--fg);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    display: flex; flex-direction: column;
  }
  header {
    display: flex; align-items: center; gap: 1rem;
    padding: .55rem 1rem; border-bottom: 1px solid var(--border);
    background: var(--panel);
  }
  header h1 { margin: 0; font-size: 1rem; font-weight: 600; }
  header .spacer { flex: 1; }
  header a { color: var(--fg-dim); text-decoration: none; font-size: .85rem; margin-left: .75rem; }
  header a:hover { color: var(--fg); }
  header .crumb { font-size: .85rem; color: var(--fg-dim); }
  header .crumb b { color: var(--fg); font-weight: 600; }
  main {
    flex: 1; display: grid;
    grid-template-columns: 260px 1fr;
    gap: 1px; background: var(--border);
    min-height: 0;
  }
  aside {
    background: var(--panel); overflow: auto;
    padding: .5rem 0; min-width: 0;
  }
  aside .group {
    font-size: .7rem; text-transform: uppercase; letter-spacing: .08em;
    color: var(--fg-dim); padding: .65rem .85rem .25rem;
  }
  aside ul { list-style: none; margin: 0; padding: 0; }
  aside li a {
    display: block; padding: .25rem .85rem .25rem 1.4rem;
    color: var(--fg); text-decoration: none;
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-size: .82rem; line-height: 1.4;
    border-left: 2px solid transparent;
  }
  aside li a:hover { background: var(--panel-2); }
  aside li a.active {
    background: var(--panel-2);
    border-left-color: var(--accent);
    color: var(--accent);
  }
  aside li a .size {
    color: var(--fg-dim); float: right; font-size: .72rem;
  }
  section.viewer {
    background: var(--panel); display: flex; flex-direction: column;
    min-height: 0; min-width: 0;
  }
  .viewer-header {
    font-size: .75rem;
    color: var(--fg-dim);
    padding: .4rem .85rem; border-bottom: 1px solid var(--border);
    display: flex; align-items: center; gap: .75rem;
  }
  .viewer-header .path {
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    color: var(--fg); font-size: .82rem;
  }
  .viewer-header .spacer { flex: 1; }
  .viewer-header a, .viewer-header button {
    color: var(--fg-dim); text-decoration: none; font-size: .78rem;
    background: transparent; border: 1px solid var(--border);
    border-radius: 6px; padding: .25rem .55rem; cursor: pointer;
    font-family: inherit;
  }
  .viewer-header a:hover, .viewer-header button:hover {
    color: var(--fg); border-color: var(--fg-dim);
  }
  #editor { flex: 1; width: 100%; min-height: 0; display: none; }
  #editor.ready { display: block; }
  .empty {
    flex: 1; display: flex; align-items: center; justify-content: center;
    color: var(--fg-dim); font-size: .9rem;
  }
</style>
</head>
<body>
<header>
  <h1>NURL Stdlib</h1>
  <span class="crumb" id="crumb">— pick a module —</span>
  <div class="spacer"></div>
  <a href="/" target="_self">← Playground</a>
  <a href="/readme" target="_blank" rel="noopener">README</a>
  <a href="/grammar" target="_blank" rel="noopener">Grammar</a>
</header>

<main>
  <aside id="tree"></aside>
  <section class="viewer">
    <div class="viewer-header">
      <span class="path" id="currentPath">(no file)</span>
      <span class="spacer"></span>
      <a id="rawLink" href="#" target="_blank" rel="noopener" hidden>raw</a>
      <button id="copyBtn" type="button" hidden>copy</button>
    </div>
    <div id="editor"></div>
    <div id="emptyMsg" class="empty">Select a stdlib module on the left to view it.</div>
  </section>
</main>

<script src="https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs/loader.js"></script>
<script>
  window.__monacoReady = new Promise((resolve) => {
    require.config({ paths: { vs: 'https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs' } });
    require(['vs/editor/editor.main'], () => resolve(window.monaco));
  });
</script>

<script type="module">
const NURL_MONARCH = {
  defaultToken: "",
  tokenPostfix: ".nurl",
  tokenizer: {
    root: [
      [/\\/\\/.*$/, "comment"],
      [/`/, { token: "string.quote", bracket: "@open", next: "@string" }],
      [/\\$(?=\\s*`)/, "keyword.control.import"],
      [/&(?=\\s*`)/,  "keyword.control.ffi"],
      [/(@)(\\s+)([a-z_][\\w]*)/, ["keyword.other.func", "white", "entity.name.function"]],
      [/(%)(\\s+)([A-Za-z_][\\w]*)/, ["keyword.other.trait", "white", "type.identifier"]],
      [/(:)(\\s*)(\\|)(\\s*)([A-Za-z_][\\w]*)/,
        ["keyword", "white", "keyword", "white", "type.identifier"]],
      [/(:)(\\s+)([A-Z][\\w]*)(\\s*)(\\{)/,
        ["keyword", "white", "type.identifier", "white", "@brackets"]],
      [/\\d+\\.\\d+([eE][+\\-]?\\d+)?/, "number.float"],
      [/\\d+/,                       "number"],
      [/\\b(T|F)\\b/, "constant.language.boolean"],
      [/\\b(i|u|f|b|s|v)\\b/, "type"],
      [/\\b[A-Z][\\w]*\\b/, "type.identifier"],
      [/→/,              "keyword.operator"],
      [/\\^/,             "keyword.control.return"],
      [/\\?\\?/,           "keyword.control"],
      [/\\?/,             "keyword.control"],
      [/~/,              "keyword.control"],
      [/;/,              "keyword"],
      [/\\\\/,             "keyword"],
      [/\\bZ\\b/,          "keyword"],
      [/(==|!=|<=|>=)/,  "keyword.operator"],
      [/[<>]/,           "keyword.operator"],
      [/[+\\-*/%]/,       "keyword.operator.arithmetic"],
      [/[&|!]/,          "keyword.operator.logical"],
      [/[=:]/,           "keyword.operator.assign"],
      [/[.#@$]/,         "keyword.operator"],
      [/[{}()\\[\\]]/, "@brackets"],
      [/,/,          "delimiter"],
      [/[a-zA-Z_]\\w*/, "identifier"],
      [/\\s+/, "white"],
    ],
    string: [
      [/\\\\[ntr\\\\`]/,                                    "string.escape"],
      [/[^\\\\`]+/,                                       "string"],
      [/`/, { token: "string.quote", bracket: "@close", next: "@pop" }],
    ],
  },
};

const NURL_THEME_RULES = [
  { token: "comment",                     foreground: "6A9955", fontStyle: "italic" },
  { token: "string",                      foreground: "CE9178" },
  { token: "string.quote",                foreground: "CE9178" },
  { token: "string.escape",               foreground: "D7BA7D" },
  { token: "number",                      foreground: "B5CEA8" },
  { token: "number.float",                foreground: "B5CEA8" },
  { token: "constant.language.boolean",   foreground: "569CD6" },
  { token: "type",                        foreground: "4EC9B0" },
  { token: "type.identifier",             foreground: "4EC9B0" },
  { token: "entity.name.function",        foreground: "DCDCAA" },
  { token: "keyword",                     foreground: "C586C0" },
  { token: "keyword.control",             foreground: "C586C0" },
  { token: "keyword.control.import",      foreground: "C586C0" },
  { token: "keyword.control.ffi",         foreground: "C586C0" },
  { token: "keyword.control.return",      foreground: "C586C0" },
  { token: "keyword.other.func",          foreground: "569CD6" },
  { token: "keyword.other.trait",         foreground: "569CD6" },
  { token: "keyword.operator",            foreground: "D4D4D4" },
  { token: "keyword.operator.arithmetic", foreground: "D4D4D4" },
  { token: "keyword.operator.logical",    foreground: "D4D4D4" },
  { token: "keyword.operator.assign",     foreground: "D4D4D4" },
  { token: "identifier",                  foreground: "9CDCFE" },
  { token: "delimiter",                   foreground: "D4D4D4" },
];

const $ = (sel) => document.querySelector(sel);
const tree = $("#tree");
const crumb = $("#crumb");
const currentPath = $("#currentPath");
const rawLink = $("#rawLink");
const copyBtn = $("#copyBtn");
const editorHost = $("#editor");
const emptyMsg = $("#emptyMsg");

let editor = null;
let allFiles = [];

function groupFiles(files) {
  const groups = new Map();
  for (const f of files) {
    const i = f.path.indexOf("/");
    const top = i < 0 ? "(root)" : f.path.slice(0, i);
    if (!groups.has(top)) groups.set(top, []);
    groups.get(top).push(f);
  }
  return groups;
}

function renderTree(files) {
  tree.innerHTML = "";
  const groups = groupFiles(files);
  for (const [top, items] of groups) {
    const h = document.createElement("div");
    h.className = "group";
    h.textContent = top + "/";
    tree.appendChild(h);
    const ul = document.createElement("ul");
    for (const f of items) {
      const li = document.createElement("li");
      const a = document.createElement("a");
      a.href = "?path=" + encodeURIComponent(f.path);
      a.dataset.path = f.path;
      const labelLeaf = f.path.includes("/") ? f.path.slice(f.path.lastIndexOf("/") + 1) : f.path;
      const labelSpan = document.createElement("span");
      labelSpan.textContent = labelLeaf;
      const sizeSpan = document.createElement("span");
      sizeSpan.className = "size";
      sizeSpan.textContent = f.bytes + " B";
      a.appendChild(labelSpan);
      a.appendChild(sizeSpan);
      a.addEventListener("click", (ev) => {
        ev.preventDefault();
        selectPath(f.path, true);
      });
      li.appendChild(a);
      ul.appendChild(li);
    }
    tree.appendChild(ul);
  }
}

function highlightActive(path) {
  for (const a of tree.querySelectorAll("a")) {
    a.classList.toggle("active", a.dataset.path === path);
  }
}

async function ensureEditor() {
  if (editor) return editor;
  const monaco = await window.__monacoReady;
  if (!monaco.languages.getLanguages().some((l) => l.id === "nurl")) {
    monaco.languages.register({ id: "nurl" });
    monaco.languages.setMonarchTokensProvider("nurl", NURL_MONARCH);
    monaco.languages.setLanguageConfiguration("nurl", {
      comments: { lineComment: "//" },
      brackets: [["{","}"],["[","]"],["(",")"]],
    });
    monaco.editor.defineTheme("nurl-dark", {
      base: "vs-dark",
      inherit: true,
      rules: NURL_THEME_RULES,
      colors: {
        "editor.background": "#161a21",
        "editor.foreground": "#e6e8ee",
        "editorLineNumber.foreground": "#4b5366",
        "editorCursor.foreground": "#7cc4ff",
      },
    });
  }
  editor = monaco.editor.create(editorHost, {
    value: "",
    language: "nurl",
    theme: "nurl-dark",
    fontFamily: 'ui-monospace, "SF Mono", Menlo, Consolas, monospace',
    fontSize: 13,
    lineHeight: 1.45,
    minimap: { enabled: true },
    scrollBeyondLastLine: false,
    readOnly: true,
    domReadOnly: true,
    automaticLayout: true,
    smoothScrolling: true,
    tabSize: 2,
    insertSpaces: true,
  });
  return editor;
}

async function selectPath(path, push) {
  if (!path) return;
  const r = await fetch("/stdlib/" + path.split("/").map(encodeURIComponent).join("/"));
  if (!r.ok) {
    crumb.textContent = "load failed: " + path;
    return;
  }
  const j = await r.json();
  const ed = await ensureEditor();
  emptyMsg.style.display = "none";
  editorHost.classList.add("ready");
  ed.setValue(j.source);
  ed.setScrollTop(0);
  currentPath.textContent = "stdlib/" + path;
  crumb.innerHTML = "stdlib / <b>" + path.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b>";
  rawLink.href = "/stdlib/" + path.split("/").map(encodeURIComponent).join("/");
  rawLink.hidden = false;
  copyBtn.hidden = false;
  document.title = "NURL · " + path;
  highlightActive(path);
  if (push) {
    const url = new URL(window.location.href);
    url.searchParams.set("path", path);
    history.pushState({ path }, "", url);
  }
}

copyBtn.addEventListener("click", async () => {
  if (!editor) return;
  try {
    await navigator.clipboard.writeText(editor.getValue());
    const old = copyBtn.textContent;
    copyBtn.textContent = "copied";
    setTimeout(() => { copyBtn.textContent = old; }, 900);
  } catch (e) {}
});

window.addEventListener("popstate", () => {
  const p = new URLSearchParams(window.location.search).get("path");
  if (p) selectPath(p, false);
});

(async function init() {
  try {
    const r = await fetch("/stdlib");
    allFiles = await r.json();
  } catch (e) {
    crumb.textContent = "failed to load /stdlib index";
    return;
  }
  renderTree(allFiles);
  const initialPath = new URLSearchParams(window.location.search).get("path");
  if (initialPath) {
    selectPath(initialPath, false);
  }
})();
</script>
</body>
</html>
"""

_TESTS_VIEWER_HTML = (
    _STDLIB_VIEWER_HTML
    .replace("NURL Stdlib · Browser", "NURL Tests · Browser")
    .replace("<h1>NURL Stdlib</h1>", "<h1>NURL Tests</h1>")
    .replace("Select a stdlib module on the left to view it.", "Select a compiler test on the left to view it.")
    .replace('fetch("/stdlib/"', 'fetch("/tests/"')
    .replace('fetch("/stdlib")', 'fetch("/tests")')
    .replace('"/stdlib/" + path', '"/tests/" + path')
    .replace('"stdlib/" + path', '"compiler/tests/" + path')
    .replace('"stdlib / <b>" + path.replace', '"compiler/tests / <b>" + path.replace')
    .replace('rawLink.href = "/stdlib/"', 'rawLink.href = "/tests/"')
    .replace('crumb.textContent = "failed to load /stdlib index"', 'crumb.textContent = "failed to load /tests index"')
)


@router.get("/stdlib-viewer", response_class=HTMLResponse, tags=["stdlib"], include_in_schema=False,
            summary="Browsable Monaco-highlighted viewer for stdlib modules")
def stdlib_viewer() -> HTMLResponse:
    return HTMLResponse(_STDLIB_VIEWER_HTML)


@router.get("/stdlib", response_model=list[StdlibInfo], tags=["stdlib"])
def list_stdlib() -> list[StdlibInfo]:
    return [StdlibInfo(**entry) for entry in _list_nu_files(NURL_STDLIB_DIR)]


@router.get("/stdlib/{name:path}", response_model=StdlibContent, tags=["stdlib"])
def get_stdlib_module(name: str) -> StdlibContent:
    target = _safe_under(NURL_STDLIB_DIR, name, label="stdlib module")
    source = target.read_text(encoding="utf-8", errors="replace")
    return StdlibContent(name=name, source=source, bytes=len(source.encode("utf-8")))


@router.get("/tests-viewer", response_class=HTMLResponse, tags=["tests"], include_in_schema=False,
            summary="Browsable Monaco-highlighted viewer for compiler tests")
def tests_viewer() -> HTMLResponse:
    return HTMLResponse(_TESTS_VIEWER_HTML)


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


@router.get("/license", response_class=HTMLResponse, tags=["docs"],
            summary="Dual-license overview (MIT OR Apache-2.0)")
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


@router.get("/license/apache", response_class=HTMLResponse, tags=["docs"], summary="Render LICENSE-APACHE (Apache 2.0)")
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


@router.get("/grammar", response_class=HTMLResponse, tags=["docs"], summary="Render the current NURL grammar (spec/grammar.ebnf)")
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
