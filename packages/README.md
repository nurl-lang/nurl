# NURL registry packages

Real, publishable packages that exercise the NURL package ecosystem end to
end — the compiler's installed-stdlib resolution (`$NURL_STDLIB`), the
package manager's dependency resolution, and `nurlpkg install <name>`
(fetch + build + install a program from the registry onto `$PATH`).

These are **registry** packages, deliberately *not* part of the core
stdlib: every CLI wants argument parsing, but the shape of a parser is
opinionated enough that it belongs to the ecosystem, not the language.

## `argz/` — a tiny argument parser (library)

Dependency-free. Boolean flags, value options (`--name X` / `--name=X`),
short aliases (`-n`), a `--` end-of-options separator, positional
arguments, and an auto-generated `--help` body. Leak-clean under
AddressSanitizer/LeakSanitizer.

```
( argz_new prog about )           → Argz
( argz_flag p long short help )   → v        bool flag
( argz_opt  p long short help )   → v        value option
( argz_parse p argv )             → ! ArgzMatch ArgzErr
( argz_has   m long )             → b
( argz_value m long )             → ?String  (borrows)
( argz_positionals m )            → ( Vec String )  (borrows)
( argz_help  p )                  → String
```

## `argz-demo/` — a friendly greeter (installable program)

Declares `argz = "^0.1"` as a registry dependency and ships a `src/main.nu`
entry point, so it can be installed as a binary:

```
nurlpkg install argz-demo
argz-demo --name World            # Hello, World!
argz-demo --name World --shout    # HELLO, WORLD!
argz-demo alice bob               # Hello, alice! / Hello, bob!
```

`nurlpkg install <name>` fetches the package, resolves its dependencies
into `./deps/`, compiles `src/main.nu` with the installed compiler against
the shipped stdlib (found via `$NURL_STDLIB`), and drops the binary in
`$NURL_HOME/bin` (default `~/.nurl/bin`, which `install-toolchain.sh` puts
on `$PATH`).

## `nq/` — a jq-lite JSON query tool (installable program)

A genuinely useful everyday utility: read JSON from stdin (or `--file`),
apply a small jq-like filter, and print it pretty (default), compact
(`-c`), or raw (`-r`). Like `argz-demo`, it declares `argz = "^0.1"` as a
registry dependency for flag parsing; for the JSON itself it leans on the
shipped `stdlib/ext/json`. Leak-clean under ASan/LSan across every path.

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
the NURL playground's doc viewer, extracted into the registry. Depends on
`argz` for flags; leak-clean under ASan/LSan.

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
a reusable renderer library (`src/chart.nu`). Pure NURL, no FFI; depends on
`argz` for flags; leak-clean under ASan/LSan.

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

## The full loop

```bash
./build.sh                          # build the compiler
./tools/nurlpkg/build.sh            # build the package manager
./tools/install-toolchain.sh        # install nurlc + nurlpkg + stdlib to ~/.nurl
source ~/.nurl/env                  # NURL_STDLIB + PATH

nurlpkg install argz-demo           # fetch + build + install from the registry
argz-demo --shout hello             # HELLO, HELLO!
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
nurlpkg install argz-demo
argz-demo --shout hello
```

`nurlpkg install <name>` is shell-free and cross-platform: it stages under
the platform temp dir, resolves the tool's dependencies in-process, copies
the built binary with the language's own filesystem primitives, and runs
the build driver (`nurl.sh` / `nurl.bat`) without any POSIX coreutils. The
compiler finds the shipped stdlib via `$NURL_STDLIB` on both platforms.

### Bin convention

An installable program is any package with a `src/main.nu` entry point; the
installed binary takes the package's name. A package without `src/main.nu`
is a library (like `argz`) and `nurlpkg install <name>` reports it as such.
