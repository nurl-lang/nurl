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
claude mcp add nurl -- nurl-mcp
```

For any other client, configure an MCP server whose `command` is `nurl-mcp`
(no arguments).

## Tools

| Tool | Arguments | Does |
|---|---|---|
| `nurl_build` | `source` *or* `path` | Compile with the local toolchain; report success or compiler diagnostics. Does not run the program. |
| `nurl_run` | `source` *or* `path` | Compile **and** run; return the program's exit code, stdout, and stderr. |
| `nurl_check` | `source` *or* `path` | Front-end only — type-check + borrow-check, no binary. Fast. |
| `nurl_fmt` | `source` *or* `path` | Format to canonical form (`nurlfmt`); return the formatted source. |
| `nurl_list_stdlib` | — | List the `.nu` modules in the installed stdlib (`$NURL_STDLIB`). |
| `nurl_read_stdlib` | `name` | Read one stdlib module by path relative to the stdlib root (e.g. `core/string.nu`). |

`source` is inline NURL; `path` is a `.nu` file on the host. Inline source is
written to a unique temp file that is deleted after the call (build artifacts
too — the server leaves nothing behind).

## Security

`nurl_run` is **arbitrary code execution**: NURL programs link libc and can make
any syscall — there is no sandbox (unlike the playground's container). Over
stdio this is safe, because only the process that spawned the server can talk to
it. A network transport (`--http`, with token auth and a `--read-only` mode that
omits `run`) is intentionally **deferred to a later version**; this one is
stdio-only by design.

## Status

v0.1.0 — first cut. Not yet bundled with the toolchain; install it explicitly.
Possible follow-ups: the `--http`/token network mode; serving the grammar / spec
/ examples once the installer ships them; a `nurl_doc` tool.
