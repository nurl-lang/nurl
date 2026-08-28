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

## Declaring a dependency

```toml
[dependencies]
onnx  = { path = "../onnx", version = "^0.4.2" }   # monorepo path + registry version
chart = "^0.1.1"                                     # registry-only, shorthand
```

`path` drives local/monorepo builds (resolved by symlink; `nurlpkg install`
links it under `deps/`). The `version` is the requirement used when the same
dependency is fetched from the registry, so a monorepo build and a
registry install agree on what's acceptable. `nurlpkg` always resolves a
registry dependency to the **newest published version that satisfies the
requirement** (`semver_req_max_satisfying`).

### Version requirement syntax

The dialect is **identical to npm** (node-semver):

| Syntax | Meaning |
| --- | --- |
| `1.2.3` | **exact** — a bare, fully-specified version is a pin, no wiggle room |
| `*` · `x` · `""` | any version |
| `1.x` · `1.2.x` · `1` · `1.2` | **X-range** — wildcard/omitted segment (`1` ≡ `1.x`, `1.2` ≡ `1.2.x`) |
| `^1.2.3` | **caret** — newest compatible (below) |
| `~1.2.3` | **tilde** — newest patch: `>=1.2.3 <1.3.0` |
| `>=1.2.3 <2.0.0` | explicit range — space-separated comparators are **AND**-ed |
| `1.2.3 - 2.3.4` | inclusive **hyphen** range: `>=1.2.3 <=2.3.4` |
| `^1.0.0 \|\| ^2.0.0` | **OR** — matches if any side matches |

Comparators are `=`, `>`, `>=`, `<`, `<=`; a partial completes with an X-range
(`>1.2` ⇒ `>=1.3.0`, `<2` ⇒ `<2.0.0`).

**`^` (caret)** admits changes that don't touch the left-most non-zero
segment — the everyday choice:

| Requirement | Range | Admits |
| --- | --- | --- |
| `^1.2.3` | `>=1.2.3 <2.0.0` | `1.2.3` … `1.9.9`, not `2.0.0` |
| `^0.2.3` | `>=0.2.3 <0.3.0` | `0.2.x >= 0.2.3`, not `0.3.0` |
| `^0.0.3` | `>=0.0.3 <0.0.4` | only `0.0.3` |

For a `0.x` package caret locks the **minor** (`^0.2.3` won't jump to `0.3.0`),
so every `0.x` package here pins deps with `^` and bumps its **minor** on a
breaking change, **patch** on a fix.

**`~` (tilde)** allows patch-level moves only: `~1.2.3` ⇒ `>=1.2.3 <1.3.0`,
`~1.2` ⇒ `>=1.2.0 <1.3.0`, `~1` ⇒ `>=1.0.0 <2.0.0`.

**Convention:** depend with `^<version>` (newest compatible); a bare `1.2.3`
pins exactly — use it only when you must. The engine is
`stdlib/ext/semver.nu`.

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

## `lsmdb/` — a crash-safe key/value store (installable program **and** library)

A real LSM tree in pure NURL: a write-ahead log, a skip-list memtable over
a byte arena, immutable SSTables with a CRC-32 per block, a Bloom filter
and a block index, ordered range scans, compaction, and snapshot reads.
An acknowledged write is fsynced before `put` returns; every crash point
in the flush and compact sequences recovers to a correct state; a torn log
tail loses exactly the write that was never acknowledged; and a block that
fails its checksum fails the read rather than returning something wrong.

```
nurlpkg install lsmdb
lsmdb put user:42 '{"name":"ada"}'   # durable when it returns
lsmdb scan --from user: --limit 20   # ordered, half-open range
lsmdb get user:42 --at 7             # the database as of write #7
lsmdb compact                        # merge tables, reclaim space

# …or depend on the store itself:
#   [dependencies]
#   lsmdb = "^0.1"
#   $ `deps/lsmdb/src/lsmdb.nu`
#   : !*Lsm String db ( lsm_open `/var/db/things` )
```

Opening a table reads only its index and filter, and a get reads exactly
the one block it needs, so a table larger than RAM is an ordinary table.
Leak-clean under ASan/LSan across every path. See
[`lsmdb/README.md`](lsmdb/README.md) for the file format and the guarantees.

## `pqc/` — post-quantum cryptography, and whether the web is ready (installable program)

Both halves of the migration over
[`stdlib/std/mlkem.nu`](../stdlib/std/mlkem.nu) and
[`stdlib/std/mldsa.nu`](../stdlib/std/mldsa.nu): **ML-KEM** (FIPS 203,
formerly CRYSTALS-Kyber) for key encapsulation and **ML-DSA** (FIPS 204,
formerly CRYSTALS-Dilithium) for signatures, at all three parameter sets
each, checked byte for byte against NIST's own ACVP vectors — 660
published cases. No libcrypto, no liboqs; the binary links libc and
nothing else.

```
nurlpkg install pqc
pqc keygen -o demo             # demo.ek (1184 B) + demo.dk (2400 B)
pqc encaps demo.ek -o demo.ct  # → ciphertext + shared secret
pqc decaps demo.dk demo.ct     # → the same shared secret
pqc sign-keygen -o id          # id.pub (1952 B) + id.key (4032 B)
pqc sign id.key report.pdf     # → report.pdf.sig (3309 B)
pqc verify id.pub report.pdf report.pdf.sig
pqc probe cloudflare.com github.com   # who actually does post-quantum TLS?
pqc bench                      # ~15k keygen/s, ~16k encaps/s on one core
pqc kat                        # self-test against the NIST vectors
```

`pqc probe` is the part worth having on a laptop. It completes a real
TLS 1.3 handshake and reports the key-exchange group the server chose:

```
host                              PQ?  group
cloudflare.com                    PQ   X25519MLKEM768
www.google.com                    PQ   X25519MLKEM768
github.com                        no   x25519
```

That distinction is otherwise invisible. Offering the hybrid group is
not the same as getting it — a server without ML-KEM falls back to
X25519, the handshake succeeds, and nothing says so; traffic to it is
recordable today and decryptable later. The probe works because
`stdlib/std/tls.nu` offers `X25519MLKEM768` first by default, so every
`tls_connect` in the tree already negotiates it where it can.

## `zst/` — Zstandard, with no Zstandard underneath (installable program)

RFC 8878 in pure NURL, both directions, over
[`stdlib/std/zstd.nu`](../stdlib/std/zstd.nu): frames with or without a
declared content size, raw / RLE / compressed blocks, Huffman literals in
one or four bitstreams with a tree that is itself FSE-compressed or
repeated from the previous block, FSE sequences in all four table modes,
the repeat offsets, skippable frames, concatenated frames, and the XXH64
content checksum. The binary links libc and nothing else.

```
nurlpkg install zst
zst c archive.tar          # → archive.tar.zst, readable by unzstd
zst d archive.tar.zst      # and back
zst t *.zst                # verify structure, sizes and checksum
zst i archive.tar.zst      # every frame and block, and how each was coded
zst b archive.tar          # what this machine actually does
cat x | zst c | zst d | cmp - x    # a byte-clean filter, NULs and all
```

`zst i` is the part no other tool gives you: per block, whether the
literals went raw, RLE or Huffman (one stream or four, tree sent or
repeated), how many sequences it carries, and whether each of the three
sequence tables was predefined, sent, RLE or repeated. That is the view
you want when a file compresses worse than expected — `zstd --list`
stops at the frame.

Levels 13–19 run an optimal parse — a priced shortest path over each
block, repriced from its own choices — and on a 200 kB text corpus
level 19 beats `zstd -19` outright. Interoperability is checked against
the reference CLI in both directions by `tools/zstd_gate.sh`: reference
frames at every level decode byte-identically, frames produced here
pass `zstd -t` and decode through `zstd -d`, mutated frames are refused
without a crash or a hang, and resident size is flat across hundreds of
round trips. See [`zst/README.md`](zst/README.md).

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

Stdio by default; an optional `--http` transport adds bearer-token auth
(`--token`), a `--read-only` mode, and gates code execution behind `--allow-run`
(a non-loopback bind refuses to start without a token). `nurl_run` is real code
execution with no sandbox — hence those guards. See
[`nurl-mcp/README.md`](nurl-mcp/README.md).

## `mermaid-server/` — mermaid flowcharts to SVG (installable program)

An HTTP server that renders mermaid `flowchart` source to an SVG image,
and — in the same process, on the same port — an MCP server that does the
same for an agent. Pure NURL: no headless browser, no `node_modules`, no
mermaid.js. Multi-threaded, one worker per CPU.

```
nurlpkg install mermaid-server
mermaid-server                                     # HTTP + MCP on :8808
curl -s --data-binary @flow.mmd :8808/render > flow.svg
claude mcp add mermaid -- mermaid-server --stdio   # or wire it into an agent
```

Nothing about the look is compiled in: every colour, width, radius, font
and gap comes from a *template* — a TOML file read from an external
directory at startup and picked per request by name, with per-shape and
per-line-style overrides and a raw-CSS escape hatch. Adding a look is
adding a file. `default`, `dark` and `blueprint` ship with the package.

Also a one-shot CLI (`mermaid-server render diagram.mmd -o diagram.svg`)
and a self-contained live playground at `/`. See
[`mermaid-server/README.md`](mermaid-server/README.md) for the supported
mermaid subset, the layout passes and the template key set.

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
