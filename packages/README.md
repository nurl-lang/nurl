# NURL registry packages

Real, publishable packages that exercise the NURL package ecosystem end to
end — the compiler's installed-stdlib resolution (`$NURL_STDLIB`), the
package manager's dependency resolution, and `nurlpkg install <name>`
(fetch + build + install a program from the registry onto `$PATH`).

These are **registry** packages — real, useful CLIs and libraries, *not*
part of the core stdlib. Command-line argument parsing is itself now a
stdlib facility (`std/args` — flags, value options, clustered shorts,
`--`, positionals, an auto-generated `--help`), so the tools below just
`$ ` import `stdlib/std/args.nu` and need no parser dependency of their own.

`nurlpkg install <name>` fetches a package, resolves its dependencies into
`./deps/`, compiles `src/main.nu` with the installed compiler against the
shipped stdlib (found via `$NURL_STDLIB`), and drops the binary in
`$NURL_HOME/bin` (default `~/.nurl/bin`, which `install-toolchain.sh` puts
on `$PATH`).

## `nq/` — a jq-lite JSON query tool (installable program)

A genuinely useful everyday utility: read JSON from stdin (or `--file`),
apply a small jq-like filter, and print it pretty (default), compact
(`-c`), or raw (`-r`). It parses flags with the stdlib `std/args`; for
the JSON itself it leans on the shipped `stdlib/ext/json`. Leak-clean under
ASan/LSan across every path.

```
nurlpkg install nq
echo '{"items":[{"id":1},{"id":2}]}' | nq '.items[].id'   # 1 / 2
echo '{"user":{"name":"Ada"}}'       | nq -r .user.name   # Ada
echo '{"a":1,"b":2}'                 | nq -c '. | keys'    # ["a","b"]
```

Supported filters: `.`, `.path.to.field` (with `.0` / `[0]` indexing), a
trailing `[]` to iterate an array/object (one result per line, optionally
projecting `.field` from each), and the `| keys` / `| length` terminals.
See [`nq/README.md`](nq/README.md) for the full grammar.

## `md2html/` — Markdown → HTML (installable program **and** library)

Renders Markdown to HTML. Ships both as an installable CLI (`md2html`,
reading stdin or `--file`, with an optional `--full` styled page) and as a
reusable renderer library (`src/markdown.nu`, one function `md_to_html`)
that other packages can depend on. The renderer is the same one that powers
the NURL playground's doc viewer, extracted into the registry. Parses
flags with the stdlib `std/args`; leak-clean under ASan/LSan.

```
nurlpkg install md2html
md2html < README.md              # HTML fragment
md2html -f README.md --full      # complete styled page

# …or depend on the renderer library:
#   [dependencies]
#   md2html = "^0.1"
#   $ `deps/md2html/src/markdown.nu`
#   : String html ( md_to_html ( string_data src ) )
```

See [`md2html/README.md`](md2html/README.md) for the supported Markdown and
the library API.

## `chart/` — terminal charts (installable program **and** library)

Turns a stream of numbers into something you can see: a one-line
sparkline, labelled horizontal bars, a histogram, or a line/scatter plot —
all drawn with Unicode block elements at eighth-cell resolution. Ships as
an installable CLI (`chart`, reading numbers from stdin or `--file`) and as
a reusable renderer library (`src/chart.nu`). Pure NURL, no FFI; parses
flags with the stdlib `std/args`; leak-clean under ASan/LSan.

```
nurlpkg install chart
seq 1 20 | chart spark                                   # ▁▁▂▂▂▃▃▄▄▄▅▅▅▆▆▇▇▇██
ls -l | awk '{print $5}' | chart hist --bins 8           # size distribution
printf '%s\n' 'apples 8.5' 'pears 6' | chart bar         # labelled bars
chart line -f temps.txt --height 12                      # line plot from a file

# …or depend on the renderer library:
#   [dependencies]
#   chart = "^0.1"
#   $ `deps/chart/src/chart.nu`
#   : String spark ( chart_sparkline values )
```

Modes: `spark` (sparkline), `bar` (one `<label> <value>` per line), `hist`
(`--bins N`), and `line` (`--width`/`--height`). See
[`chart/README.md`](chart/README.md) for the full CLI and library API.

## `nurl-mcp/` — a local MCP server for the toolchain (installable program)

The LLM-facing counterpart of `nurl-lsp`: a [Model Context
Protocol](https://modelcontextprotocol.io) server (newline-delimited JSON-RPC
over stdio) that exposes the *locally installed* compiler to an agent, so it can
`nurl_build` / `nurl_run` / `nurl_check` / `nurl_fmt` NURL against the host's
real files and read the installed stdlib (`nurl_list_stdlib` / `nurl_read_stdlib`).
Unlike the cloud playground MCP, it drives *your* toolchain over *your* files,
offline. Built on the `stdlib/ext/mcp.nu` primitives; libc-only.

```
nurlpkg install nurl-mcp
claude mcp add nurl -- nurl-mcp     # wire into an MCP client (spawned over stdio)
```

`nurl_run` is real code execution with no sandbox, which is why the server is
stdio-only (only its spawner can reach it); a token-authenticated `--http` mode
is deferred. See [`nurl-mcp/README.md`](nurl-mcp/README.md).

## The full loop

```bash
./build.sh                          # build the compiler
./tools/nurlpkg/build.sh            # build the package manager
./tools/install-toolchain.sh        # install nurlc + nurlpkg + stdlib to ~/.nurl
source ~/.nurl/env                  # NURL_STDLIB + PATH

nurlpkg install nq                  # fetch + build + install from the registry
echo '{"a":[1,2,3]}' | nq '.a[]'    # 1 / 2 / 3
```

A self-contained reproduction (a local static registry, no account needed)
lives in `tools/nurlpkg/test-install-tool.sh`.

## Windows

The same loop works on Windows with the `.bat` counterparts:

```bat
build.bat
tools\nurlpkg\build.bat
tools\install-toolchain.bat       :: installs to %USERPROFILE%\.nurl
call %USERPROFILE%\.nurl\env.bat   :: NURL_STDLIB + PATH for this session
nurlpkg install nq
echo {"a":1} | nq .a
```

`nurlpkg install <name>` is shell-free and cross-platform: it stages under
the platform temp dir, resolves the tool's dependencies in-process, copies
the built binary with the language's own filesystem primitives, and runs
the build driver (`nurl.sh` / `nurl.bat`) without any POSIX coreutils. The
compiler finds the shipped stdlib via `$NURL_STDLIB` on both platforms.

### Bin convention

An installable program is any package with a `src/main.nu` entry point; the
installed binary takes the package's name. A package without `src/main.nu`
is a library (e.g. the `markdown` / `chart` renderer modules) and
`nurlpkg install <name>` reports it as such.
