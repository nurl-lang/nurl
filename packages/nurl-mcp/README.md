# `nurl-mcp` — a local MCP server for the NURL toolchain

`nurl-mcp` exposes the **locally installed** NURL toolchain to an LLM agent over
the [Model Context Protocol](https://modelcontextprotocol.io). It is the
LLM-facing counterpart of `nurl-lsp`: where `nurl-lsp` serves editors over LSP,
`nurl-mcp` serves an agent over MCP so it can build, run, type-check, and format
NURL on the host — against the real filesystem and the exact compiler + stdlib
you have installed.

This is deliberately **not** the broad playground MCP at
<https://play.nurl-lang.org/mcp> (sandboxed cloud builds, cross-compile to every
target). `nurl-mcp` is small, local, and offline: its value is that it drives
*your* toolchain over *your* files — something a remote server cannot do.

It is written in NURL and itself built on the `stdlib/ext/mcp.nu` primitives
(the same library the playground server uses), so it stays libc-only.

## Install

```sh
nurlpkg install nurl-mcp        # → ~/.nurl/bin/nurl-mcp
```

It shells out to `nurl`, `nurlc`, and `nurlfmt`, which the toolchain installer
(`tools/install-toolchain.sh`) puts on `$PATH` along with `$NURL_STDLIB`. Make
sure those are present (`nurlc --version`-style smoke test: `echo '@ main → i { ^ 0 }' | …`).

## Wire it into a client

The transport is newline-delimited JSON-RPC 2.0 over **stdio** — the transport
every MCP client supports. The client spawns the binary and talks to it over the
pipe; nothing listens on the network.

```sh
# Claude Code
claude mcp add nurl -- ~/.nurl/bin/nurl-mcp
```

`nurlpkg install` prints this exact line once the binary is in place. The `~`
is expanded by your shell, so the absolute path works even from a client that
doesn't inherit your `$PATH`; `claude mcp add nurl -- nurl-mcp` also works when
`~/.nurl/bin` is on `$PATH`.

For any other client, configure an MCP server whose `command` is
`~/.nurl/bin/nurl-mcp` (no arguments).

## Tools

| Tool | Arguments | Does |
|---|---|---|
| `nurl_build` | `source` *or* `path` | Compile with the local toolchain; report success or compiler diagnostics. Does not run the program. |
| `nurl_build_wasm` | `source` *or* `path`, optional `out` | Compile to a **wasm32-wasi module**, fully locally (wasmbuilder package — no build service). `out` = output path; a `path` input defaults to `<input>.wasm`; inline `source` without `out` keeps the module + its `.ll` at a temp path and returns JSON with `wasm_path` / `ll_path` (no inline base64). |
| `nurl_run` | `source` *or* `path` | Compile **and** run; return the program's exit code, stdout, and stderr. |
| `nurl_check` | `source` *or* `path` | Front-end only — type-check + borrow-check, no binary. Fast. |
| `nurl_fmt` | `source` *or* `path` | Format to canonical form (`nurlfmt`); return the formatted source. |
| `nurl_list_stdlib` | — | List the `.nu` modules in the installed stdlib (`$NURL_STDLIB`). |
| `nurl_read_stdlib` | `name` | Read one stdlib module by path relative to the stdlib root (e.g. `core/string.nu`). |
| `nurl_api` | `module` \| `package` \| `query` | A module's API surface via nurldoc (signatures + doc comments + type definitions, no bodies — `ext/csv.nu` is 63 KB, its surface 11 KB), or an AND-term search over every module's declarations. A query no single declaration satisfies is re-run as a **whole-word OR ranked by coverage** — `string builder append` still lands on `string_push_bytes`, `vec_push new string_new` on `string_new` and `vec_push` — and only if that finds nothing does the reply widen to the package registry; an exact package-name term is footnoted regardless. |
| `nurl_grep` | `pattern`, `where?`, `word?` | Case-insensitive search over the installed stdlib (`path:line:` hits, word-boundary matches ranked first) and the registry's package names + descriptions — "is there a package for X" from any MCP-only editor. |
| `nurl_docs` | `name?`, `section?`, `outline?`, `query?`, `offset?` | The shipped `docs/` tree — the questions the API surface cannot answer: `MEMORY.md` (who frees what, and when), `CRYPTO.md`, `ASYNC.md`, `PLATFORMS.md`, `spec.md`, `dev/COMPILER_INTERNALS.md`, … No `name` lists everything with its size and title. `query='string_free manually managed handles'` searches every **section** of every document and returns the best few with their `section=` keys. `name=X outline=true` is that document's heading map; `name=X section='7.4'` (a number, or words from the heading) is one section — 3 KB instead of MEMORY.md's 44 KB, and the only way to read a slice of `spec.md`, which is past the 48 KB per-call cap. `name=X` alone still returns the whole document, paged with `offset`. Served from `$NURL_DOCS`, else `$NURL_STDLIB/docs` — `install-toolchain.sh` puts it there. |

`source` is inline NURL; `path` is a `.nu` file on the host. Inline source is
written to a unique temp file that is deleted after the call (build artifacts
too — the server leaves nothing behind).

## Transports

**stdio** (default) — described above; the client spawns the binary and talks
over the pipe. Nothing listens on the network.

**HTTP** (`--http`) — the MCP **Streamable HTTP** transport, served through
the stdlib facade (`ext/mcp_http.nu`, the same plumbing swarm-mcp uses):
`POST /mcp` single requests **and JSON-RPC batches**, `GET /mcp` SSE probe,
`Mcp-Session-Id` echo, `DELETE /mcp`, CORS + preflight. Bearer-token auth
wraps the whole endpoint. For clients that speak MCP over HTTP or when the
agent runs elsewhere.

```
nurl-mcp --http [--host ADDR] [--port N] [--token TOK] [--read-only] [--allow-run]
```

| Flag | Default | Meaning |
|---|---|---|
| `--http` | off (stdio) | Serve over HTTP instead of stdio. |
| `--host ADDR` | `127.0.0.1` | Bind address. |
| `--port N` | `8080` | Bind port. |
| `--token TOK` | none | Require `Authorization: Bearer TOK` on every request (401 otherwise). |
| `--read-only` | off | Expose only `nurl_check`, `nurl_fmt`, `nurl_list_stdlib`, `nurl_read_stdlib`, `nurl_api`, `nurl_grep`, `nurl_docs` — no build, no run. |
| `--allow-run` | off | Allow `nurl_run` over HTTP (see Security). |

```
# loopback dev server, run enabled, no auth (warns):
nurl-mcp --http --allow-run

# exposed on the LAN — token is mandatory:
nurl-mcp --http --host 0.0.0.0 --port 8080 --token "$(head -c32 /dev/urandom | base64)" --allow-run
```

## Security

`nurl_run` is **arbitrary code execution**: NURL programs link libc and can make
any syscall — there is no sandbox (unlike the playground's container).

- **stdio:** `nurl_run` is always available — only the process that spawned the
  server can reach it.
- **HTTP:** `nurl_run` is **disabled by default** and must be turned on with
  `--allow-run`. It is not even advertised in `tools/list` until then.
- **Non-loopback binds require a token.** `--http --host 0.0.0.0` (anything that
  isn't `127.0.0.1` / `::1` / `localhost`) **refuses to start** without
  `--token`. A loopback HTTP server with no token starts but warns.
- **`--read-only`** removes `nurl_build`, `nurl_build_wasm`, and `nurl_run` entirely (on any
  transport), leaving only analysis/read tools — the mode to expose when you
  only want the agent to inspect, not execute.

Tool availability is enforced twice: disabled tools are omitted from
`tools/list` *and* refused (with an explanatory error) if called directly.

`nurl_run` is **arbitrary code execution**: NURL programs link libc and can make
any syscall — there is no sandbox (unlike the playground's container). Over
stdio this is safe, because only the process that spawned the server can talk to
it. A network transport (`--http`, with token auth and a `--read-only` mode that
omits `run`) is intentionally **deferred to a later version**; this one is
stdio-only by design.

## Status

v0.4.1 — stdio + token-authenticated HTTP transport. Not yet bundled with the
toolchain; install it explicitly. Possible follow-ups: serving the grammar /
spec / examples once the installer ships them (a `nurl_doc` tool); a continuous
SSE notification stream; per-session state.
