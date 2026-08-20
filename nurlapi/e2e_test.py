#!/usr/bin/env python3
"""End-to-end tests for the pure-NURL nurlapi MCP/HTTP server.

Drives a *running* server (default http://127.0.0.1:8000) over HTTP and
exercises both the REST surface (/health, /mcp-info, /build*, /examples,
/stdlib, /tests, /download/{token}, OAuth stubs) and the JSON-RPC MCP
surface at POST /mcp (initialize, tools/list, tools/call, resources/list,
resources/read, prompts/list, prompts/get, ping, batches, notifications,
malformed input, unknown methods, traversal guards, session id header).

Stdlib-only (urllib + json) so it runs in any container the server runs
in.  Exit code 0 = all green, 1 = at least one failure (full diff +
counter-summary printed at the end).

Usage:
    python3 nurlapi/e2e_test.py                # http://127.0.0.1:8000
    python3 nurlapi/e2e_test.py --base URL     # custom base
    python3 nurlapi/e2e_test.py --quick        # skip the slow build test
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

# ── plumbing ────────────────────────────────────────────────────────

PASS = 0
FAIL = 0
FAILS: list[str] = []


def _color(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if sys.stdout.isatty() else text


def ok(name: str) -> None:
    global PASS
    PASS += 1
    print(_color("32", "  PASS"), name)


def bad(name: str, why: str) -> None:
    global FAIL
    FAIL += 1
    FAILS.append(f"{name}: {why}")
    print(_color("31", "  FAIL"), name, "—", why)


def assert_eq(name: str, got: Any, want: Any) -> None:
    if got == want:
        ok(name)
    else:
        bad(name, f"expected {want!r}, got {got!r}")


def assert_true(name: str, cond: bool, why: str = "") -> None:
    if cond:
        ok(name)
    else:
        bad(name, why or "condition false")


# ── HTTP helpers ────────────────────────────────────────────────────


def _parse_sse_single(text: str) -> str | None:
    """Parse a single-event SSE frame ``event: …\\ndata: <json>\\n…``.

    Concatenates every ``data:`` line of the (only) event we care about
    into a single string. Returns None if no data line is found.
    """
    data_lines: list[str] = []
    for line in text.splitlines():
        if line.startswith("data:"):
            # Spec says strip exactly one leading space after the colon.
            v = line[5:]
            if v.startswith(" "):
                v = v[1:]
            data_lines.append(v)
    if not data_lines:
        return None
    return "\n".join(data_lines)


class Client:
    def __init__(self, base: str) -> None:
        self.base = base.rstrip("/")

    def _req(
        self,
        method: str,
        path: str,
        *,
        body: bytes | None = None,
        headers: dict[str, str] | None = None,
        timeout: float = 60.0,
    ) -> tuple[int, dict[str, str], bytes]:
        url = self.base + path
        req = urllib.request.Request(url, data=body, method=method)
        for k, v in (headers or {}).items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.status, dict(resp.headers), resp.read()
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers or {}), e.read() or b""

    def get(self, path: str, **kw: Any) -> tuple[int, dict[str, str], bytes]:
        return self._req("GET", path, **kw)

    def post(
        self,
        path: str,
        payload: Any,
        *,
        headers: dict[str, str] | None = None,
        raw: bool = False,
        timeout: float = 60.0,
    ) -> tuple[int, dict[str, str], bytes]:
        h = {"Content-Type": "application/json"}
        if headers:
            h.update(headers)
        body = payload if raw else json.dumps(payload).encode()
        return self._req("POST", path, body=body, headers=h, timeout=timeout)

    def delete(self, path: str, **kw: Any) -> tuple[int, dict[str, str], bytes]:
        return self._req("DELETE", path, **kw)

    # Convenience: JSON-RPC call returning parsed envelope (or None for
    # 202/empty body, e.g. notifications-only batches).
    def rpc(
        self,
        body: Any,
        *,
        headers: dict[str, str] | None = None,
        timeout: float = 60.0,
    ) -> tuple[int, dict[str, str], Any | None]:
        h = {"Accept": "application/json, text/event-stream"}
        if headers:
            h.update(headers)
        status, hdrs, raw = self.post("/mcp", body, headers=h, timeout=timeout)
        if not raw:
            return status, hdrs, None
        ctype = (hdrs.get("Content-Type") or hdrs.get("content-type") or "").lower()
        text = raw.decode("utf-8", errors="replace")
        # Streamable-HTTP transport: replies come back framed as a single
        # `event: message\ndata: <json>\n` SSE chunk.
        if "text/event-stream" in ctype:
            payload = _parse_sse_single(text)
            if payload is None:
                return status, hdrs, raw  # type: ignore[return-value]
            try:
                return status, hdrs, json.loads(payload)
            except json.JSONDecodeError:
                return status, hdrs, raw  # type: ignore[return-value]
        try:
            return status, hdrs, json.loads(text)
        except json.JSONDecodeError:
            return status, hdrs, raw  # type: ignore[return-value]


# ── tests ───────────────────────────────────────────────────────────


def t_health(c: Client) -> None:
    print("\n[REST] /health")
    status, _, raw = c.get("/health")
    assert_eq("status 200", status, 200)
    j = json.loads(raw)
    assert_eq("status=ok", j.get("status"), "ok")
    assert_eq("nurlc_available", j.get("nurlc_available"), True)
    assert_true("stdlib_modules non-empty", bool(j.get("stdlib_modules")))


def t_mcp_info(c: Client) -> None:
    print("\n[REST] /mcp-info")
    status, _, raw = c.get("/mcp-info")
    assert_eq("status 200", status, 200)
    j = json.loads(raw)
    assert_eq("transport", j.get("transport"), "streamable-http")
    assert_eq("url_path", j.get("url_path"), "/mcp")
    tools = j.get("tools", [])
    assert_eq("19 tools advertised", len(tools), 19)
    for t in (
        "nurl_build_native",
        "nurl_build_wasm",
        "nurl_list_examples",
        "nurl_read_grammar",
        "nurl_docs",
        "nurl_changelog",
        "nurl_api",
        "nurl_grep",
    ):
        assert_true(f"tool {t} listed", t in tools)
    # Reverse-proxy scheme signal: with X-Forwarded-Proto: https the
    # advertised absolute URLs must say https (the CF Worker sets this;
    # without it the http tunnel scheme would leak into OAuth metadata).
    status, _, raw = c.get("/mcp-info", headers={"X-Forwarded-Proto": "https"})
    assert_eq("fwd-proto status 200", status, 200)
    fwd = json.loads(raw)
    fwd_url = (
        fwd.get("client_config_example", {})
        .get("mcpServers", {})
        .get("nurl", {})
        .get("url", "")
    )
    if os.environ.get("E2E_EXPECT_ABSOLUTE_DOWNLOADS") == "1":
        # An env-pinned public URL deliberately outranks the forwarded
        # scheme — assert the pin held instead.
        assert_true("env-pinned base outranks fwd-proto", fwd_url.startswith("http"))
    else:
        assert_true("X-Forwarded-Proto: https yields https URL", fwd_url.startswith("https://"))

    assert_true(
        "client_config_example.mcpServers.nurl.url ends in /mcp",
        j.get("client_config_example", {})
        .get("mcpServers", {})
        .get("nurl", {})
        .get("url", "")
        .endswith("/mcp"),
    )


def t_initialize(c: Client) -> str:
    print("\n[MCP] initialize")
    status, hdrs, env = c.rpc(
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}
    )
    assert_eq("status 200", status, 200)
    sid = hdrs.get("Mcp-Session-Id") or hdrs.get("mcp-session-id") or ""
    assert_true("Mcp-Session-Id header set", bool(sid), "missing session id")
    assert_true("envelope is dict", isinstance(env, dict))
    assert_eq("jsonrpc 2.0", env.get("jsonrpc"), "2.0")
    assert_eq("echoed id", env.get("id"), 1)
    res = env.get("result", {})
    assert_true("result.protocolVersion", isinstance(res.get("protocolVersion"), str))
    assert_true("result.serverInfo.name", isinstance(res.get("serverInfo", {}).get("name"), str))
    assert_true("result.capabilities.tools", "tools" in res.get("capabilities", {}))
    return sid


def t_session_echo(c: Client, sid: str) -> None:
    print("\n[MCP] session id echo")
    status, hdrs, _ = c.rpc(
        {"jsonrpc": "2.0", "id": 2, "method": "ping"},
        headers={"Mcp-Session-Id": sid},
    )
    assert_eq("status 200", status, 200)
    echo = hdrs.get("Mcp-Session-Id") or hdrs.get("mcp-session-id")
    assert_eq("session id round-trips", echo, sid)


def t_ping(c: Client) -> None:
    print("\n[MCP] ping")
    _, _, env = c.rpc({"jsonrpc": "2.0", "id": 99, "method": "ping"})
    assert_eq("ping result is {}", env.get("result"), {})


def t_tools_list(c: Client) -> None:
    print("\n[MCP] tools/list")
    _, _, env = c.rpc({"jsonrpc": "2.0", "id": 3, "method": "tools/list"})
    tools = env.get("result", {}).get("tools", [])
    assert_eq("19 tools", len(tools), 19)
    names = {t.get("name") for t in tools}
    for required in (
        "nurl_build_native",
        "nurl_build_wasm",
        "nurl_build_windows",
        "nurl_build_macos",
        "nurl_build_target",
        "nurl_list_examples",
        "nurl_read_example",
        "nurl_list_stdlib",
        "nurl_read_stdlib",
        "nurl_list_tests",
        "nurl_read_test",
        "nurl_read_grammar",
        "nurl_read_readme",
        "nurl_read_roadmap",
        "nurl_docs",
        "nurl_changelog",
        "nurl_api",
        "nurl_grep",
    ):
        assert_true(f"tools/list has {required}", required in names)
    # Each tool has description + inputSchema.
    for t in tools:
        if not (isinstance(t.get("description"), str) and isinstance(t.get("inputSchema"), dict)):
            bad("tool descriptor shape", f"bad shape for {t.get('name')!r}")
            return
    ok("every tool has description + inputSchema")


def _tool_text(env: dict) -> str:
    """Pull out the joined text-block payload from a tools/call result."""
    res = env.get("result", {})
    parts = res.get("content", [])
    return "".join(p.get("text", "") for p in parts if p.get("type") == "text")


def _tool_call(c: Client, name: str, args: dict) -> dict:
    _, _, env = c.rpc(
        {
            "jsonrpc": "2.0",
            "id": 100,
            "method": "tools/call",
            "params": {"name": name, "arguments": args},
        },
        timeout=120.0,
    )
    return env  # type: ignore[return-value]


def t_tools_call_listing(c: Client) -> None:
    print("\n[MCP] tools/call nurl_list_examples")
    env = _tool_call(c, "nurl_list_examples", {})
    text = _tool_text(env)
    try:
        j = json.loads(text)
    except json.JSONDecodeError:
        bad("nurl_list_examples result is JSON text", f"got: {text[:120]!r}")
        return
    assert_true("nurl_list_examples returned an array", isinstance(j, list))
    names = [x.get("name", x.get("path", "")) for x in j]
    assert_true(
        "examples listing mentions hello.nu or collatz.nu",
        any("hello" in n or "collatz" in n for n in names),
    )

    print("\n[MCP] tools/call nurl_list_stdlib + nurl_list_tests")
    for tool in ("nurl_list_stdlib", "nurl_list_tests"):
        env = _tool_call(c, tool, {})
        text = _tool_text(env)
        try:
            j = json.loads(text)
            assert_true(f"{tool} returns non-empty array", isinstance(j, list) and len(j) > 0)
        except json.JSONDecodeError:
            bad(f"{tool} returns JSON", f"got: {text[:120]!r}")


def t_tools_call_reads(c: Client) -> None:
    print("\n[MCP] tools/call nurl_read_grammar / nurl_read_readme")
    for tool in ("nurl_read_grammar", "nurl_read_readme", "nurl_read_roadmap"):
        env = _tool_call(c, tool, {})
        text = _tool_text(env)
        assert_true(f"{tool} returns non-empty text", len(text) > 100, f"len={len(text)}")

    print("\n[MCP] tools/call nurl_read_stdlib name=core/string.nu")
    env = _tool_call(c, "nurl_read_stdlib", {"name": "core/string.nu"})
    text = _tool_text(env)
    assert_true("core/string.nu returned (non-empty)", len(text) > 0)


def t_tools_call_changelog(c: Client) -> None:
    print("\n[MCP] tools/call nurl_changelog (index / query / release / no-match)")

    # Index mode: no arguments → release index with entry counts.
    env = _tool_call(c, "nurl_changelog", {})
    text = _tool_text(env)
    assert_true("index lists releases", "releases," in text and "[Unreleased]" in text)
    assert_true("index shows entry counts", " entries" in text)

    # Query mode: every release heading carries a date, so 'compiler'
    # is a safe always-matching term; entries come back with provenance.
    env = _tool_call(c, "nurl_changelog", {"query": "compiler", "limit": 2})
    text = _tool_text(env)
    assert_true("query header reports match counts", " changelog entries match query 'compiler'" in text)
    assert_true("entries carry [release] provenance", "\n[" in text)

    # limit respected: at most 2 entry blocks (3 with header+footer parts).
    assert_true("limit caps emitted entries", text.count("\n\n[") <= 2)

    # Release filter alone returns that release's entries.
    env = _tool_call(c, "nurl_changelog", {"release": "Unreleased", "limit": 1})
    text = _tool_text(env)
    assert_true("release filter scopes to heading", "in release 'Unreleased'" in text)

    # No-match path gives actionable guidance instead of silence.
    env = _tool_call(c, "nurl_changelog", {"query": "zzz-no-such-term-zzz"})
    text = _tool_text(env)
    assert_true("no-match has guidance", "No matches" in text)


def t_build_native_run_optin(c: Client) -> None:
    print("\n[MCP] nurl_build_native run= (opt-in, off by default)")

    src = "@ main \u2192 i { ( nurl_print `run opt-in\\n` ) ^ 4 }"
    env = _tool_call(c, "nurl_build_native", {"source": src, "run": True})
    try:
        payload = json.loads(_tool_text(env))
    except json.JSONDecodeError:
        bad("build_native run returns JSON", "reply was not JSON")
        return

    run = payload.get("run")
    assert_true("run= is answered, never ignored", run is not None,
                "no 'run' key: a caller that asked to run must not get silence")

    if os.environ.get("E2E_EXPECT_RUN_ENABLED") == "1":
        # Operator turned it on: the program's own output comes back.
        assert_eq("exit code round-trips", run.get("exit_code"), 4)
        assert_true("stdout round-trips", "run opt-in" in (run.get("stdout") or ""))
    else:
        # Default posture. The refusal has to say what to do about it —
        # both the switch and the sandboxed alternative — or the caller
        # is left guessing why an artifact appeared and no output did.
        err = run.get("error") or ""
        assert_true("run refused by default", bool(err))
        assert_true("refusal names the switch", "NURL_ALLOW_RUN" in err)
        assert_true("refusal names the sandboxed path", "unikernel" in err)
        assert_true("build itself still succeeded",
                    payload.get("binary_artifact") is not None)


def t_tools_call_docs(c: Client) -> None:
    print("\n[MCP] tools/call nurl_docs (index / read / forgiving names / paging)")

    # No arguments → the index of everything under docs/.
    env = _tool_call(c, "nurl_docs", {})
    text = _tool_text(env)
    assert_true("index reports a count", "document(s) under docs/" in text)
    assert_true("index lists MEMORY.md", "MEMORY.md" in text)
    assert_true("index lists a nested doc", "dev/COMPILER_INTERNALS.md" in text)
    assert_true("index carries titles", "NURL Memory Model" in text)

    # Exact name.
    env = _tool_call(c, "nurl_docs", {"name": "CRYPTO.md"})
    text = _tool_text(env)
    assert_true("read echoes the path", text.startswith("docs/CRYPTO.md"))
    assert_true("read returns the body", "Cryptography & TLS" in text)

    # The 'docs/' prefix, the '.md' suffix and the case are all optional,
    # and a basename reaches a nested document.
    for name in ("memory", "MEMORY.md", "docs/MEMORY.md", "./memory.md"):
        env = _tool_call(c, "nurl_docs", {"name": name})
        text = _tool_text(env)
        assert_true(f"name {name!r} resolves to MEMORY.md", text.startswith("docs/MEMORY.md"))
    env = _tool_call(c, "nurl_docs", {"name": "COMPILER_INTERNALS"})
    assert_true(
        "basename reaches the nested doc",
        _tool_text(env).startswith("docs/dev/COMPILER_INTERNALS.md"),
    )

    # spec.md is past the 48 KB cap: the reply says where it stopped and
    # the printed offset returns the rest.
    env = _tool_call(c, "nurl_docs", {"name": "spec"})
    text = _tool_text(env)
    assert_true("oversize doc is truncated", "truncated at" in text)
    assert_true("truncation names the next offset", "continue with offset=" in text)
    off = int(text.split("continue with offset=")[1].split()[0])
    env = _tool_call(c, "nurl_docs", {"name": "spec", "offset": off})
    text = _tool_text(env)
    assert_true("offset page reports its range", f"[bytes {off}" in text)

    # outline=true — the heading map, a fraction of the document.
    env = _tool_call(c, "nurl_docs", {"name": "MEMORY.md", "outline": True})
    outline = _tool_text(env)
    assert_true("outline reports the section count", "sections. Ask for one with section=" in outline)
    assert_true("outline lists a numbered section", "7.4 Manually-managed handles" in outline)

    # section= by number, and by words from the heading — both reach the
    # same section, and it is a fraction of the 44 KB document.
    env = _tool_call(c, "nurl_docs", {"name": "MEMORY", "section": "7.4"})
    by_num = _tool_text(env)
    assert_true("section by number", by_num.startswith("docs/MEMORY.md \u203a 7.4 Manually-managed handles"))
    env = _tool_call(c, "nurl_docs", {"name": "MEMORY", "section": "manually-managed"})
    by_words = _tool_text(env)
    assert_true("section by words reaches the same one", by_words.startswith("docs/MEMORY.md \u203a 7.4"))

    env = _tool_call(c, "nurl_docs", {"name": "MEMORY.md"})
    whole = _tool_text(env)
    assert_true(
        "a section costs a fraction of the document",
        len(by_num) * 4 < len(whole),
        f"section {len(by_num)}B vs document {len(whole)}B",
    )

    # spec.md is past the per-call cap, so before this it could not be
    # read in one call at all. A section of it can.
    env = _tool_call(c, "nurl_docs", {"name": "spec", "section": "4.9"})
    assert_true("oversize doc still yields one section", _tool_text(env).startswith("docs/spec.md \u203a 4.9"))

    # A section miss answers with the outline, not a bare error.
    env = _tool_call(c, "nurl_docs", {"name": "MEMORY", "section": "99.9"})
    assert_true("section miss errors", bool(env.get("result", {}).get("isError")))
    assert_true("section miss shows the outline", "sections. Ask for one with section=" in _tool_text(env))

    # query= searches every section of every document.
    env = _tool_call(c, "nurl_docs", {"query": "string_free manually managed handles"})
    q = _tool_text(env)
    assert_true("query reports a section count", "documentation section(s) match" in q)
    assert_true("query finds the handle section", "7.4 Manually-managed handles" in q)
    assert_true("query hands back a section key", "[section=7.4]" in q)
    assert_true(
        "query returns sections, not whole documents",
        len(q) * 2 < len(whole),
        f"query {len(q)}B vs document {len(whole)}B",
    )

    env = _tool_call(c, "nurl_docs", {"query": "zzzqqq wwwxxx qqzzwwx"})
    assert_true("dead query says so", "Nothing matched" in _tool_text(env))

    # Traversal is refused, and an unknown name answers with the index
    # rather than a bare error.
    env = _tool_call(c, "nurl_docs", {"name": "../../etc/passwd"})
    assert_true("traversal refused", bool(env.get("result", {}).get("isError")))
    env = _tool_call(c, "nurl_docs", {"name": "no-such-doc"})
    res = env.get("result", {})
    assert_true("unknown name errors", bool(res.get("isError")))
    assert_true("unknown name lists what exists", "document(s) under docs/" in _tool_text(env))


def t_tools_call_api(c: Client) -> None:
    print("\n[MCP] tools/call nurl_api (module / query / errors)")

    # Module mode: csv.nu's API surface — signatures + type definitions,
    # no function bodies, __-private helpers omitted.
    env = _tool_call(c, "nurl_api", {"module": "ext/csv.nu"})
    text = _tool_text(env)
    assert_true("module renders header prose", "CSV reader/writer" in text)
    assert_true("module renders signatures", "csv_reader_next" in text)
    assert_true("module renders type fields", "quote_char" in text)
    assert_true("module omits function bodies", "string_push_char" not in text)
    assert_true("module omits __-private helpers", "__csv_drop_string" not in text)

    # Query mode: AND-matched terms over declaration blocks.
    env = _tool_call(c, "nurl_api", {"query": "csv quote"})
    text = _tool_text(env)
    assert_true("query reports match count", "declaration(s) match" in text)
    assert_true("query finds the dialect struct", "CSVDialect" in text)

    # Exact-name footer: 'http' matches hundreds of stdlib declarations,
    # AND is a registry package — the reply must carry the one-line note
    # with the package's real pitch (needs network to reg.nurl-lang.org).
    env = _tool_call(c, "nurl_api", {"query": "http"})
    text = _tool_text(env)
    assert_true("declarations found for http", "declaration(s) match 'http'" in text)
    assert_true("exact-name footer present", "Note: the registry has a package named 'http'" in text)
    assert_true("footer carries the README pitch", "unified HTTP server interface" in text)

    # 0-hit widening: 'calculator' exists in examples but no stdlib
    # declaration carries it — the same reply must surface the example.
    # One term, so the OR pass (which needs two) never runs.
    env = _tool_call(c, "nurl_api", {"query": "calculator"})
    text = _tool_text(env)
    assert_true("0-hit reports widening", "widened the search" in text)
    assert_true("0-hit lists the example", "examples/calculator.nu" in text)
    assert_true("example carries its blurb", "expression evaluator" in text)

    # Concept queries: no declaration holds all the terms, so the same
    # terms are re-run as a whole-word OR ranked by coverage. This has to
    # answer with the real functions instead of jumping to the registry.
    env = _tool_call(c, "nurl_api", {"query": "vec_push new string_new"})
    text = _tool_text(env)
    assert_true("OR pass announces itself", "matching ANY term as a whole word" in text)
    assert_true("OR pass labels coverage", "[2/3 terms]" in text)
    assert_true("OR pass finds string_new", "string_new" in text)
    assert_true("OR pass finds vec_push", "vec_push" in text)
    assert_true("OR hit suppresses the corpus widening", "widened the search" not in text)

    env = _tool_call(c, "nurl_api", {"query": "hash map insert"})
    text = _tool_text(env)
    assert_true("OR pass reaches the hashmap module", "std/hashmap.nu" in text)

    # Whole-word only: 'string' must reach string_push_str, never a
    # declaration whose only claim is the word 'substring'.
    env = _tool_call(c, "nurl_api", {"query": "string builder append"})
    text = _tool_text(env)
    assert_true("OR pass ranks by module", "core/string.nu" in text)

    # Nothing anywhere: two terms, no whole-word hit either — the corpus
    # widening still has to run.
    env = _tool_call(c, "nurl_api", {"query": "zzzqqq wwwxxx"})
    text = _tool_text(env)
    assert_true("dead query still widens", "widened the search" in text)

    # Errors: unknown module, and neither argument.
    env = _tool_call(c, "nurl_api", {"module": "ext/zzz-nope.nu"})
    assert_true("unknown module errors", bool(env.get("result", {}).get("isError")))
    env = _tool_call(c, "nurl_api", {})
    assert_true("missing args errors", bool(env.get("result", {}).get("isError")))


def t_tools_call_grep(c: Client) -> None:
    print("\n[MCP] tools/call nurl_grep (stdlib scope / caps / missing pattern)")

    env = _tool_call(c, "nurl_grep", {"pattern": "time_format", "where": "stdlib"})
    text = _tool_text(env)
    assert_true("grep reports line count", "line(s) match" in text)
    assert_true("grep returns path:line hits", "stdlib/std/time.nu:" in text)

    # Boundary ranking, no flags needed: 'mcp' is a memcpy substring. The
    # default output must put boundary-clean lines (the ext/mcp family)
    # FIRST and every memcpy line under the labeled in-word tail.
    env = _tool_call(c, "nurl_grep", {"pattern": "mcp", "where": "stdlib"})
    text = _tool_text(env)
    assert_true("boundary hits found", "ext/mcp" in text)
    assert_true("in-word tail labeled", "— matches inside longer words" in text)
    sep = text.index("— matches inside longer words")
    assert_true("mcp family ranked before the tail", text.index("ext/mcp") < sep)
    # `( memcpy` is the raw libc-call form — it never coexists with a
    # boundary-clean 'mcp' on the same line (a doc comment ABOUT the
    # boundary rule legitimately mentions both words, hence not plain
    # 'memcpy' here).
    assert_true("memcpy calls only in the tail", "( memcpy" not in text[:sep] and "( memcpy" in text[sep:])
    # Letters-only boundary: 'http' at a digit boundary (http2_*) is clean.
    env = _tool_call(c, "nurl_grep", {"pattern": "http", "where": "stdlib", "word": True})
    text = _tool_text(env)
    assert_true("digit boundary is clean (http2)", "http2" in text)
    # word=true drops the tail entirely but reports the filtered count.
    env = _tool_call(c, "nurl_grep", {"pattern": "mcp", "where": "stdlib", "word": True})
    text = _tool_text(env)
    assert_true("word=true drops memcpy calls", "( memcpy" not in text)
    assert_true("word=true reports filtered count", "filtered out" in text)

    env = _tool_call(c, "nurl_grep", {"pattern": "zzz-no-such-thing-zzz", "where": "stdlib"})
    text = _tool_text(env)
    assert_true("grep no-match reports zero", text.startswith("0 line(s)"))

    env = _tool_call(c, "nurl_grep", {})
    assert_true("missing pattern errors", bool(env.get("result", {}).get("isError")))


def t_tools_call_traversal(c: Client) -> None:
    print("\n[MCP] tools/call traversal guard")
    env = _tool_call(c, "nurl_read_example", {"name": "../../../etc/passwd"})
    res = env.get("result", {})
    text = _tool_text(env)
    assert_true(
        "traversal flagged as error (isError or no etc/passwd content)",
        bool(res.get("isError")) or ("root:" not in text),
    )


def t_tools_call_unknown(c: Client) -> None:
    print("\n[MCP] tools/call unknown tool")
    env = _tool_call(c, "definitely_not_a_real_tool", {})
    res = env.get("result", {})
    text = _tool_text(env)
    assert_true(
        "unknown tool flagged",
        bool(res.get("isError")) or "unknown tool" in text.lower(),
        f"got result={res!r}",
    )


def t_tools_call_build(c: Client) -> None:
    print("\n[MCP] tools/call nurl_build_native (hello world)")
    src = '@ main → i {\n  ( puts `hello-from-e2e` )\n  ^ 0\n}\n'
    t0 = time.time()
    env = _tool_call(c, "nurl_build_native", {"source": src, "filename": "hello.nu"})
    dur = time.time() - t0
    text = _tool_text(env)
    try:
        j = json.loads(text)
    except json.JSONDecodeError:
        bad("build result is JSON text", f"got: {text[:200]!r}")
        return
    print(f"  (build wall-time: {dur:.2f}s)")
    assert_true("build status field present", "status" in j, f"keys={list(j)}")
    # Some implementations call it 'success', some 'status'. Accept either.
    succeeded = j.get("status") == "ok" or j.get("success") is True or j.get("ok") is True
    if not succeeded:
        # surface stderr for debuggability before failing
        print("    build stderr:", str(j.get("stderr") or j.get("logs") or "")[:400])
    assert_true("build succeeded", succeeded, f"j keys={list(j)}")
    # Try downloading the artifact if we got a token.
    artifact = j.get("binary_artifact") or j.get("binary") or {}
    token = artifact.get("token") if isinstance(artifact, dict) else None
    url = artifact.get("url") if isinstance(artifact, dict) else None
    # download_url must be ABSOLUTE when the server exports its public URL
    # (NURL_PUBLIC_URL / NURL_API_URL) — an MCP caller on another machine
    # cannot guess the host from a bare path. The harness opts in via
    # E2E_EXPECT_ABSOLUTE_DOWNLOADS=1 when it started the server that way.
    dl = artifact.get("download_url") if isinstance(artifact, dict) else None
    if os.environ.get("E2E_EXPECT_ABSOLUTE_DOWNLOADS") == "1":
        assert_true("download_url is absolute", bool(dl) and dl.startswith("http"), f"dl={dl!r}")
    elif dl:
        assert_true("download_url shape", dl.startswith("http") or dl.startswith("/download/"), f"dl={dl!r}")
    if token:
        status, _, body = c.get(f"/download/{token}")
        assert_eq("download token → 200", status, 200)
        assert_true("download body looks like ELF", body[:4] == b"\x7fELF", f"prefix={body[:4]!r}")
    elif url:
        # url is host-relative
        path = url if url.startswith("/") else "/" + url
        status, _, body = c.get(path)
        assert_eq("download url → 200", status, 200)
        assert_true("download body looks like ELF", body[:4] == b"\x7fELF", f"prefix={body[:4]!r}")
    else:
        bad("build artifact present", f"no token/url in {j}")


def t_resources(c: Client) -> None:
    print("\n[MCP] resources/list + resources/read")
    _, _, env = c.rpc({"jsonrpc": "2.0", "id": 4, "method": "resources/list"})
    resources = env.get("result", {}).get("resources", [])
    assert_eq("7 resources", len(resources), 7)
    uris = {r.get("uri") for r in resources}
    for u in (
        "nurl://readme",
        "nurl://roadmap",
        "nurl://grammar",
        "nurl://stdlib",
        "nurl://examples",
        "nurl://tests",
    ):
        assert_true(f"resources has {u}", u in uris)

    _, _, env = c.rpc(
        {
            "jsonrpc": "2.0",
            "id": 5,
            "method": "resources/read",
            "params": {"uri": "nurl://grammar"},
        }
    )
    contents = env.get("result", {}).get("contents", [])
    assert_true("grammar resource non-empty", len(contents) > 0)
    if contents:
        assert_eq("grammar mimeType", contents[0].get("mimeType"), "text/plain")
        assert_true("grammar text non-empty", len(contents[0].get("text", "")) > 50)


def t_prompts(c: Client) -> None:
    print("\n[MCP] prompts/list + prompts/get")
    _, _, env = c.rpc({"jsonrpc": "2.0", "id": 6, "method": "prompts/list"})
    prompts = env.get("result", {}).get("prompts", [])
    assert_eq("1 prompt", len(prompts), 1)
    assert_eq("prompt name", prompts[0].get("name"), "nurl_coding_assistant")

    _, _, env = c.rpc(
        {
            "jsonrpc": "2.0",
            "id": 7,
            "method": "prompts/get",
            "params": {"name": "nurl_coding_assistant"},
        }
    )
    res = env.get("result", {})
    msgs = res.get("messages", [])
    assert_true("prompts/get returned messages", isinstance(msgs, list) and len(msgs) >= 1)


def t_method_not_found(c: Client) -> None:
    print("\n[MCP] method not found")
    _, _, env = c.rpc({"jsonrpc": "2.0", "id": 8, "method": "no/such/method"})
    err = env.get("error", {})
    assert_eq("error.code = -32601", err.get("code"), -32601)


def t_parse_error(c: Client) -> None:
    print("\n[MCP] malformed JSON → -32700")
    status, _, raw = c.post(
        "/mcp",
        b"{not json",
        raw=True,
        headers={"Accept": "application/json"},
    )
    # Server should answer with a JSON-RPC parse error envelope. 200/400 both
    # acceptable here, but body must say -32700.
    try:
        env = json.loads(raw.decode())
    except json.JSONDecodeError:
        bad("parse-error body is JSON", f"raw={raw[:120]!r}")
        return
    err = env.get("error", {})
    assert_eq("error.code = -32700", err.get("code"), -32700)
    assert_true("status 200 or 400", status in (200, 400), f"status={status}")


def t_notification(c: Client) -> None:
    print("\n[MCP] notification (no id) → empty body")
    status, _, raw = c.post(
        "/mcp",
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        headers={"Accept": "application/json"},
    )
    assert_true("status 200/202/204", status in (200, 202, 204), f"status={status}")
    assert_true("body empty for notification", len(raw.strip()) == 0, f"body={raw[:120]!r}")


def t_batch(c: Client) -> None:
    print("\n[MCP] JSON-RPC batch")
    _, _, env = c.rpc(
        [
            {"jsonrpc": "2.0", "id": "a", "method": "ping"},
            {"jsonrpc": "2.0", "method": "notifications/cancelled"},
            {"jsonrpc": "2.0", "id": "b", "method": "tools/list"},
        ]
    )
    assert_true("batch returns an array", isinstance(env, list), f"got {type(env).__name__}")
    if not isinstance(env, list):
        return
    assert_eq("batch yields 2 replies (notif dropped)", len(env), 2)
    ids = sorted(str(e.get("id")) for e in env)
    assert_eq("batch reply ids", ids, ["a", "b"])


def _sig_types(arglist: str) -> list[str]:
    """Leading type token of every comma-separated LLVM argument."""
    return [a.strip().split()[0] for a in arglist.split(",") if a.strip()]


_SHIM_DEF = re.compile(r"define (\S+) @(__nurl_\w+_shim)\(([^)]*)\)")
_SHIM_CALL = re.compile(r"call (\S+) @(__nurl_\w+_shim)\(([^)]*)\)")


def _shim_signature_mismatches(ir: str) -> list[str]:
    """Shims whose definition disagrees with how the IR calls them.

    wasm-ld does not reject that disagreement — it resolves it with a stub
    whose body is a single `unreachable`. The module links, the playground
    prints BUILD OK, and the program traps the moment the call is reached.
    """
    defs: dict[str, tuple[str, list[str]]] = {}
    for ret, name, args in _SHIM_DEF.findall(ir):
        defs[name] = (ret, _sig_types(args))
    out: list[str] = []
    for ret, name, args in _SHIM_CALL.findall(ir):
        want = defs.get(name)
        if want is None:
            out.append(f"{name}: called but never defined")
        elif (ret, _sig_types(args)) != want:
            out.append(f"{name}: defined {want}, called {(ret, _sig_types(args))}")
    return sorted(set(out))


def t_tools_call_build_unikernel(c: Client) -> None:
    # The tool's default is boot:true — an agent cannot run qemu, so the
    # guest console in the result is what makes the tool usable at all.
    print("\n[MCP] tools/call nurl_build_unikernel (boots, console in result)")
    src = "@ main → i {\n    ( nurl_println `uk-mcp-e2e` )\n    ^ 0\n}\n"
    env = _tool_call(c, "nurl_build_unikernel", {"source": src})
    text = _tool_text(env)
    try:
        j = json.loads(text)
    except json.JSONDecodeError:
        bad("unikernel tool result is JSON", f"got {text[:200]!r}")
        return
    assert_eq("unikernel tool build ok", j.get("status"), "ok")
    assert_true("tool result has elf artifact", bool((j.get("elf_artifact") or {}).get("download_url")), str(j)[:200])
    br = j.get("boot_result") or {}
    if br.get("ran") is False and "not available" in (br.get("error") or ""):
        print("  boot skipped: qemu not in this deployment")
    else:
        assert_true("tool result carries the guest console", "uk-mcp-e2e" in (br.get("log") or ""), str(br)[:200])
        assert_eq("guest exit 0 via MCP", br.get("exit"), 0)


def t_build_wasm_libc_shims(c: Client) -> None:
    print("\n[REST] /build_wasm — libc shims match their call sites")
    # `& `libc` @ rand → i` makes nurlc emit `declare i64 @rand()`, so the
    # shim wrapping wasm32's i32 `rand` has to return i64 as well. When it
    # didn't, doomfire / sand / starfield built fine and then died with
    # "runtime error: unreachable" on their first ( rand ).
    src = "& `libc` @ rand → i\n\n@ main → i {\n  : i r ( rand )\n  ^ % r 7\n}\n"
    status, _, raw = c.post(
        "/build_wasm",
        {"source": src, "filename": "randshim.nu", "emit_ll": True},
        timeout=180.0,
    )
    assert_eq("build_wasm status 200", status, 200)
    try:
        j = json.loads(raw)
    except json.JSONDecodeError:
        bad("build_wasm result is JSON", f"got {raw[:200]!r}")
        return
    assert_eq("build_wasm ok", j.get("status"), "ok")
    assert_true("wasm bytes returned", bool(j.get("wasm_base64")), f"keys={list(j)}")
    ir = j.get("llvm_ir") or ""
    assert_true("emit_ll returned the rewritten IR", "__nurl_rand_shim" in ir, "no shim in IR")
    assert_true(
        "rand shim returns i64, like its call sites",
        "define i64 @__nurl_rand_shim(" in ir,
        "; ".join(l for l in ir.splitlines() if "__nurl_rand_shim" in l)[:200],
    )
    mismatched = _shim_signature_mismatches(ir)
    assert_true("no shim/call-site signature mismatch", not mismatched, "; ".join(mismatched))


def t_build_wasm_vararg_libc(c: Client) -> None:
    print("\n[REST] /build_wasm — vararg libc declares don't poison the shims")
    # stdlib/core/io.nu FFI-declares open(2), whose IR declare carries a
    # vararg `...`. The shim generator must drop it — `... %aN` in a
    # define's parameter list is not legal LLVM, and emitting it failed
    # every wasm build whose import graph reached io.nu (this exact
    # program, examples/jira_manager.nu, …) with clang's
    # "expected ')' at end of argument list". The service used to carry
    # its own fork of the rewriter that predated the fix; it now shares
    # packages/wasmbuilder/src/wasi_ir.nu, where the drop lives.
    src = "$ `stdlib/core/io.nu`\n\n@ main → v {\n    ( nurl_print `hello\\n` )\n}\n"
    status, _, raw = c.post(
        "/build_wasm",
        {"source": src, "filename": "varargshim.nu", "emit_ll": True},
        timeout=180.0,
    )
    assert_eq("build_wasm status 200", status, 200)
    try:
        j = json.loads(raw)
    except json.JSONDecodeError:
        bad("build_wasm result is JSON", f"got {raw[:200]!r}")
        return
    assert_eq("build_wasm ok", j.get("status"), "ok")
    assert_true("wasm bytes returned", bool(j.get("wasm_base64")), f"keys={list(j)}")
    ir = j.get("llvm_ir") or ""
    bad_defines = [l for l in ir.splitlines() if l.startswith("define ") and "... %" in l]
    assert_true("no `... %aN` in shim defines", not bad_defines, "; ".join(bad_defines)[:200])


def t_build_unikernel_rest(c: Client) -> None:
    print("\n[REST] /build_unikernel — image + initfs + guards")
    # 1. A hello builds into a PVH ELF with boot commands attached.
    src = "@ main → i {\n    ( nurl_println `uk-e2e` )\n    ^ 0\n}\n"
    status, _, raw = c.post(
        "/build_unikernel",
        {"source": src, "args": "--demo yes"},
        timeout=180.0,
    )
    assert_eq("build_unikernel status 200", status, 200)
    try:
        j = json.loads(raw)
    except json.JSONDecodeError:
        bad("build_unikernel result is JSON", f"got {raw[:200]!r}")
        return
    assert_eq("build_unikernel ok", j.get("status"), "ok", )
    art = j.get("elf_artifact") or {}
    assert_true("elf artifact returned", bool(art.get("token")), f"keys={list(j)}")
    assert_true("image has a size", (j.get("image_bytes") or 0) > 50000, str(j.get("image_bytes")))
    boot = j.get("boot") or {}
    assert_true("boot.qemu names the microvm machine", "-M microvm" in (boot.get("qemu") or ""), boot.get("qemu") or "")
    assert_true("boot command carries the argv", 'args=' in (boot.get("qemu") or ""), boot.get("qemu") or "")
    assert_true("qemu_net adds virtio-net", "virtio-net-device" in (boot.get("qemu_net") or ""), "")
    # The artifact must actually download and be an ELF.
    tok = art.get("token")
    dstat, _, dbody = c.get(f"/download/{tok}")
    assert_eq("elf downloads", dstat, 200)
    assert_true("downloaded file is an ELF", dbody[:4] == b"\x7fELF", repr(dbody[:4]))

    # 2. An initfs file rides inside the image; keys are path-checked.
    import base64 as _b64
    payload = _b64.b64encode(b"uk-e2e-initfs").decode()
    status, _, raw = c.post(
        "/build_unikernel",
        {"source": src, "files": {"etc/msg.txt": payload}},
        timeout=180.0,
    )
    assert_eq("build_unikernel with files 200", status, 200)
    try:
        assert_eq("build_unikernel with files ok", json.loads(raw).get("status"), "ok")
    except json.JSONDecodeError:
        bad("files build result is JSON", f"got {raw[:200]!r}")
    for bad_key in ("../evil", "/abs", "a/../b", "a//b"):
        status, _, raw = c.post(
            "/build_unikernel",
            {"source": src, "files": {bad_key: payload}},
            timeout=60.0,
        )
        assert_eq(f"files key {bad_key!r} rejected", status, 400)

    # 3. boot:true — the server boots the image and returns the console.
    status, _, raw = c.post(
        "/build_unikernel",
        {"source": src, "boot": True},
        timeout=240.0,
    )
    assert_eq("boot:true status 200", status, 200)
    try:
        j = json.loads(raw)
        br = j.get("boot_result") or {}
        if br.get("ran") is False and "not available" in (br.get("error") or ""):
            print("  boot skipped: qemu not in this deployment")
        else:
            assert_true("boot ran", br.get("ran") is True, str(br)[:200])
            assert_true("guest printed", "uk-e2e" in (br.get("log") or ""), (br.get("log") or "")[:200])
            assert_eq("guest exited 0", br.get("exit"), 0)
    except json.JSONDecodeError:
        bad("boot result is JSON", f"got {raw[:200]!r}")

    # 4. The other architecture: same endpoint, one field.
    status, _, raw = c.post(
        "/build_unikernel",
        {"source": src.replace("uk-e2e", "uk-e2e-arm"), "arch": "aarch64", "boot": True},
        timeout=300.0,
    )
    assert_eq("aarch64 build status 200", status, 200)
    try:
        j = json.loads(raw)
        assert_eq("aarch64 build ok", j.get("status"), "ok")
        assert_eq("reply names the arch", j.get("arch"), "aarch64")
        assert_true("aarch64 boot command targets virt",
                    "-M virt" in ((j.get("boot") or {}).get("qemu") or ""),
                    (j.get("boot") or {}).get("qemu") or "")
        assert_true("aarch64 boot command has no tsc_khz (self-describing clock)",
                    "tsc_khz" not in ((j.get("boot") or {}).get("qemu") or ""), "")
        art = j.get("image_artifact") or {}
        assert_true("aarch64 build also emits the flat Image",
                    (art.get("name") or "").endswith(".Image"), str(j)[:200])
        assert_true("the Image is smaller than the ELF it came from",
                    0 < (art.get("bytes") or 0) < (j.get("image_bytes") or 0), str(art))
        istat, _, ibody = c.get(f"/download/{art.get('token')}")
        assert_eq("Image downloads", istat, 200)
        # The 64-byte ARM64 image header: magic "ARM\x64" at 0x38, and
        # code0 a branch so a loader jumping to offset 0 reaches the
        # boot code. Firecracker and cloud-hypervisor dispatch on this.
        assert_true("Image carries the ARM64 header magic",
                    ibody[0x38:0x3c] == b"ARM\x64", repr(ibody[0x38:0x3c]))
        assert_true("Image code0 is a branch",
                    ibody[3] in (0x14, 0x94), hex(ibody[3]) if ibody else "empty")
        br = j.get("boot_result") or {}
        if br.get("ran") is False and "not available" in (br.get("error") or ""):
            print("  aarch64 boot skipped: qemu not in this deployment")
        else:
            assert_true("aarch64 guest printed", "uk-e2e-arm" in (br.get("log") or ""), str(br)[:200])
            assert_eq("aarch64 guest exited 0", br.get("exit"), 0)
    except json.JSONDecodeError:
        bad("aarch64 result is JSON", f"got {raw[:200]!r}")

    # An unknown arch is refused, not silently built for the default —
    # an image that builds, downloads and does not boot is the worst
    # possible answer.
    status, _, raw = c.post(
        "/build_unikernel",
        {"source": src, "arch": "sparc"},
        timeout=60.0,
    )
    assert_eq("unknown arch rejected", status, 400)

    # 5. A broken program answers with the compiler's message, loudly.
    status, _, raw = c.post(
        "/build_unikernel",
        {"source": "@ main → i { ( nurl_println nope ) ^ 0 }"},
        timeout=60.0,
    )
    assert_eq("broken source still 200 (structured error)", status, 200)
    try:
        j = json.loads(raw)
        assert_eq("broken source status=error", j.get("status"), "error")
        assert_true(
            "stderr carries the compiler's diagnosis",
            "undefined identifier" in (j.get("stderr") or ""),
            (j.get("stderr") or "")[:200],
        )
    except json.JSONDecodeError:
        bad("broken-source result is JSON", f"got {raw[:200]!r}")


def t_tools_call_build_wasm(c: Client) -> None:
    # The MCP tool must answer with download links, never the inline
    # base64 module (which would land verbatim in the caller's context).
    print("\n[MCP] tools/call nurl_build_wasm (links, no base64)")
    src = '@ main → i {\n  ( puts `hello-wasm-mcp` )\n  ^ 0\n}\n'
    env = _tool_call(c, "nurl_build_wasm", {"source": src, "filename": "hellow.nu"})
    text = _tool_text(env)
    try:
        j = json.loads(text)
    except json.JSONDecodeError:
        bad("wasm build result is JSON text", f"got: {text[:200]!r}")
        return
    assert_eq("wasm build ok", j.get("status"), "ok")
    assert_true("no inline wasm_base64", not j.get("wasm_base64"), "base64 present")
    assert_true("no inline llvm_ir", not j.get("llvm_ir"), "llvm_ir present")
    for key, suffix in (("wasm_artifact", ".wasm"), ("ll_artifact", ".ll")):
        art = j.get(key)
        if not isinstance(art, dict):
            bad(f"{key} present", f"{key}={art!r}")
            continue
        assert_true(f"{key}.name ends {suffix}", str(art.get("name", "")).endswith(suffix))
        assert_true(f"{key}.bytes > 0", int(art.get("bytes") or 0) > 0)
        token = art.get("token")
        assert_true(f"{key}.token present", bool(token))
        status, _, body = c.get(f"/download/{token}")
        assert_eq(f"{key} download → 200", status, 200)
        if suffix == ".wasm":
            assert_true("download body is wasm", body[:4] == b"\x00asm", f"prefix={body[:4]!r}")
        else:
            assert_true("download body looks like IR", b"target triple" in body[:400])


def t_build_wasm_links_only_rest(c: Client) -> None:
    # REST default keeps the inline base64 (the playground consumes it);
    # links_only:true is the opt-out the MCP layer uses.
    print("\n[REST] /build_wasm links_only:true")
    src = '@ main → i {\n  ( puts `hello-wasm-rest` )\n  ^ 0\n}\n'
    status, _, raw = c.post(
        "/build_wasm",
        {"source": src, "filename": "hellol.nu", "links_only": True},
        timeout=180.0,
    )
    assert_eq("status 200", status, 200)
    j = json.loads(raw)
    assert_eq("build ok", j.get("status"), "ok")
    assert_true("no wasm_base64", not j.get("wasm_base64"), f"keys={list(j)}")
    assert_true("wasm_artifact present", isinstance(j.get("wasm_artifact"), dict))
    assert_true("ll_artifact present", isinstance(j.get("ll_artifact"), dict))
    assert_true("download_url still set", bool(j.get("download_url")))


def t_get_sse_and_delete(c: Client) -> None:
    print("\n[MCP] GET /mcp (SSE stub) + DELETE /mcp")
    status, hdrs, raw = c.get("/mcp")
    assert_true("GET /mcp 200/202", status in (200, 202), f"status={status}")
    ctype = hdrs.get("Content-Type", "") or hdrs.get("content-type", "")
    assert_true("GET /mcp is SSE", "text/event-stream" in ctype.lower(), f"ctype={ctype!r}")

    status, _, _ = c.delete("/mcp")
    assert_true("DELETE /mcp 2xx", 200 <= status < 300, f"status={status}")


def t_oauth_stub(c: Client) -> None:
    print("\n[REST] OAuth-protected-resource stub + /token")
    status, _, raw = c.get("/.well-known/oauth-protected-resource")
    assert_eq("oauth metadata 200", status, 200)
    j = json.loads(raw)
    assert_true("oauth resource is an /mcp URL", j.get("resource", "").endswith("/mcp"))

    status, _, raw = c.post(
        "/token",
        urllib.parse.urlencode({"grant_type": "client_credentials"}).encode(),
        raw=True,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    assert_eq("token 200", status, 200)
    j = json.loads(raw)
    assert_true("token has access_token", isinstance(j.get("access_token"), str) and j["access_token"])


# ── runner ──────────────────────────────────────────────────────────


def wait_ready(c: Client, attempts: int = 20, delay: float = 0.5) -> None:
    last = ""
    for _ in range(attempts):
        try:
            status, _, _ = c.get("/health", timeout=2.0)
            if status == 200:
                return
            last = f"status {status}"
        except Exception as e:  # pragma: no cover
            last = repr(e)
        time.sleep(delay)
    print(_color("31", f"server at {c.base} not responding to /health: {last}"))
    sys.exit(2)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8000")
    ap.add_argument("--quick", action="store_true", help="skip the slow build test")
    args = ap.parse_args()

    c = Client(args.base)
    print(f"target: {c.base}")
    wait_ready(c)

    t_health(c)
    t_mcp_info(c)

    sid = t_initialize(c)
    t_session_echo(c, sid)
    t_ping(c)

    t_tools_list(c)
    t_tools_call_listing(c)
    t_tools_call_reads(c)
    t_tools_call_changelog(c)
    t_build_native_run_optin(c)
    t_tools_call_docs(c)
    t_tools_call_api(c)
    t_tools_call_grep(c)
    t_tools_call_traversal(c)
    t_tools_call_unknown(c)
    if not args.quick:
        t_tools_call_build(c)
        t_tools_call_build_wasm(c)
        t_build_wasm_libc_shims(c)
        t_build_wasm_vararg_libc(c)
        t_build_wasm_links_only_rest(c)
        t_build_unikernel_rest(c)
        t_tools_call_build_unikernel(c)
    else:
        print("\n[MCP] tools/call nurl_build_native — skipped (--quick)")
        print("[MCP] tools/call nurl_build_wasm — skipped (--quick)")
        print("[REST] /build_wasm libc shims — skipped (--quick)")
        print("[REST] /build_wasm links_only — skipped (--quick)")
        print("[REST] /build_unikernel — skipped (--quick)")
        print("[MCP] tools/call nurl_build_unikernel — skipped (--quick)")

    t_resources(c)
    t_prompts(c)

    t_method_not_found(c)
    t_parse_error(c)
    t_notification(c)
    t_batch(c)

    t_get_sse_and_delete(c)
    t_oauth_stub(c)

    print()
    total = PASS + FAIL
    if FAIL:
        print(_color("31", f"{FAIL} failed / {total} total"))
        for line in FAILS:
            print("  -", line)
        return 1
    print(_color("32", f"all {PASS}/{total} checks passed"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
