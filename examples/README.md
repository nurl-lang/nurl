# NURL Examples

Practical NURL programs demonstrating the language and stdlib. Use
them as both reference and starting points.

## Building Examples

```bash
# Build the compiler first (if not already built)
./build.sh

# Compile and run an example via the launcher
./nurl.sh examples/fizzbuzz.nu

# Or compile manually
./build/nurlc examples/fizzbuzz.nu > /tmp/fizzbuzz.ll
clang -O2 -flto /tmp/fizzbuzz.ll stdlib/runtime.o -lm -lpthread -o /tmp/fizzbuzz
/tmp/fizzbuzz
```

## Catalogue (45 examples)

Each example is tagged for where it can run:

- **playground** — also runs on the public WASM playground at
  [play.nurl-lang.org](https://play.nurl-lang.org). Pure compute,
  stdin / argv / file I/O only, no network / no graphics / no
  secrets.
- **local** — runs only on a local build. Reasons listed in the row:
  network calls (LLM APIs, HTTP requests), server listeners, SDL2
  canvas, microphone, or API keys.

### CLI tools — file I/O, argv, no network

| File | What it does | Tag |
|---|---|---|
| [`find_clone.nu`](find_clone.nu) | grep-style search across files / directories with literal, list-of-alternatives (`--list a,b,c`), or regex (`--regex PAT`) modes. Recurses into directories, skips dotfiles, reads stdin when no PATH is given. Exit 0 on any match, 1 on no match. | playground |
| [`wordcount.nu`](wordcount.nu) | `wc`-style line / word / char counter. Demonstrates file I/O, struct, and `nurl_argv_*`. | playground |
| [`csv_demo.nu`](csv_demo.nu) | Round-trips a CSV file through `stdlib/ext/csv.nu` (RFC 4180-conformant quoting via the v2 arena writer). | playground |
| [`uuidgen.nu`](uuidgen.nu) | Emits a UUID v4 string via `stdlib/ext/uuid.nu` — quick sanity check on `nurl_rand_fill` + the hex formatter. | playground |
| [`time_basic.nu`](time_basic.nu) | Smokes the `stdlib/std/time.nu` surface: `now_ms`, `sleep_ms`, monotonic vs wall clocks. Output is intrinsically non-deterministic, so only relative orderings are asserted. | playground |

### Algorithms & control flow

| File | What it does | Tag |
|---|---|---|
| [`fizzbuzz.nu`](fizzbuzz.nu) | Classic FizzBuzz. Loops, conditionals, mutable vars. | playground |
| [`collatz.nu`](collatz.nu) | Collatz (3n+1) sequence length for a given start. | playground |
| [`calculator.nu`](calculator.nu) | Recursive-descent expression evaluator with an AST. Demonstrates enums, pattern match, Option, `\` try-propagate, heap allocation. | playground |
| [`dict_coder.nu`](dict_coder.nu) | Tiny dictionary-based text compressor + decompressor. Demonstrates `Vec[String]`, byte-level I/O. | playground |
| [`enigma.nu`](enigma.nu) | NURL stress-test: a minimal Enigma-machine evaluator. Tagged "Human readability score: 0" — exercises pattern matching, multiple `Vec`s, bit-twiddling. | playground |
| [`rule30.nu`](rule30.nu) | Wolfram's Rule 30 elementary CA — single seed → aperiodic pattern. | playground |
| [`math_basic.nu`](math_basic.nu) | `stdlib/std/float.nu` + `stdlib/std/int.nu` smoke test (libm wrappers: sqrt / sin / cos / log / exp / pow / floor / ceil / round). | playground |
| [`primordial.nu`](primordial.nu) | Primordial-soup particle chemistry — five elementary particle types, bitmask compounds, conserved momentum. Pure-text output (the canvas version below is `primordial_canvas.nu`). | playground |

### Data formats

| File | What it does | Tag |
|---|---|---|
| [`json_basic.nu`](json_basic.nu) | Full feature tour of `stdlib/ext/json.nu` — parse + stringify + accessors + Jq-style traversal. Pinned baseline output. | playground |
| [`msgpack_demo.nu`](msgpack_demo.nu) | Round-trips a user struct through MessagePack via `stdlib/ext/msgpack.nu`. | playground |
| [`serde_demo.nu`](serde_demo.nu) | Round-trips a user struct through JSON via the `stdlib/ext/serde.nu` `Serialize` trait + a hand-written `from_json` helper. The recommended shape for "make my struct serialisable". | playground |

### Language showcase

| File | What it does | Tag |
|---|---|---|
| [`showcase.nu`](showcase.nu) | Compact tour: arithmetic, control flow, structs, enums, closures, slices. Useful as a "does my fresh build work" smoke test. | playground |
| [`slice_test.nu`](slice_test.nu) | Slice literals + foreach borrow semantics + struct field access. | playground |
| [`test_05_closures_and_capture.nu`](test_05_closures_and_capture.nu) | Closure capture semantics (snapshot vs by-pointer) and the closure-as-value calling convention. | playground |
| [`test_06_torture_chamber.nu`](test_06_torture_chamber.nu) | AST construction, type inference, and memory-layout torture test. | playground |
| [`chaotic-showcase.nu`](chaotic-showcase.nu) | Adversarial three-corner stress: dense Vec3 float prefix-arithmetic, a recursive symbolic-differentiation ADT, and higher-order parser combinators (closures returning closures). | playground |
| [`chaotic-aggressor.nu`](chaotic-aggressor.nu) | A hostile pre-1.0 grammar/compiler stress test: a concatenative stack VM combining generics + monomorphisation, trait dispatch, a multi-payload `??` (or-pattern + guard + 2-payload bind), a slice-of-closures jump table, closures-returning-closures, dense prefix Horner arithmetic, const folding and LIFO `defer` — with an "aggressor lab" of minimal compiler-bug repros in its footer. | playground |

### HTTP & RPC

| File | What it does | Tag |
|---|---|---|
| [`http_basic.nu`](http_basic.nu) | `stdlib/ext/http.nu` GET + POST against httpbin.org. Gated on `NURL_HTTP_TESTS=1`. | local (network) |
| [`jsonrequest.nu`](jsonrequest.nu) | HTTP GET → parse JSON response → print fields. | local (network) |
| [`static_server.nu`](static_server.nu) | Production-shape static-file server: HTTP/1.1 keep-alive, router (`/`, `/*path`, `/api/health`, `/metrics`), Prometheus metrics, access log, `..`-rejection, graceful shutdown on Ctrl+C / SIGTERM. The canonical "did the HTTP stack work?" demo. | local (server listener) |
| [`async_http_server.nu`](async_http_server.nu) | Same handler contract as `static_server.nu` but runs the request handlers on the M:N fiber runtime. | local (server listener) |
| [`mcp_echo_server.nu`](mcp_echo_server.nu) | Minimal MCP server over stdio — one `echo` tool. Wire it into an MCP-aware client (Claude Desktop, Claude Code, etc.) and the tool is callable. | local (stdio + MCP client) |
| [`mcp_echo_server_http.nu`](mcp_echo_server_http.nu) | Same business logic as `mcp_echo_server.nu`, but exposed over HTTP transport. | local (server listener) |

### Distributed stack (NAT traversal, overlay, SWIM, CRDTs)

The pubkey-addressed overlay for distributed computing over NAT'd / mobile
peers. Full design: [`docs/DISTRIBUTED.md`](../docs/DISTRIBUTED.md).

| File | What it does | Tag |
|---|---|---|
| [`stun.nu`](stun.nu) | Discover this host's public (server-reflexive) UDP endpoint via a STUN server (`stdlib/net/stun.nu`, RFC 8489). | local (network) |
| [`nat.nu`](nat.nu) | Gather connection candidates (host + reflexive) and probe the NAT mapping type (cone → punchable vs symmetric → relay) against two public STUN servers. | local (network) |
| [`relay.nu`](relay.nu) | A deployable DERP-style relay daemon: forwards opaque datagrams by destination pubkey and fans group multicasts out — never decrypts (E2E stays in the peers). | local (server listener) |
| [`rendezvous.nu`](rendezvous.nu) | A signaling server: peers register `pubkey → candidate endpoints + relay`, others look them up by pubkey. Control plane only. | local (server listener) |
| [`transport.nu`](transport.nu) | The transport seam in use — open a pubkey-addressed transport over a relay, join a group, broadcast, receive. | local (needs a relay) |
| [`membership.nu`](membership.nu) | A SWIM membership node over the overlay: the failure detector drives the pubkey member table, probes/acks/gossip ride the transport. | local (needs a relay) |
| [`replicated_counter.nu`](replicated_counter.nu) | A PNCounter replicated across the group by CRDT gossip — each node increments its replica, broadcasts its encoded counter, merges what it receives, all converge. | local (needs a relay) |

### Databases

| File | What it does | Tag |
|---|---|---|
| [`psql.nu`](psql.nu) | A real `psql`-style PostgreSQL client on `stdlib/ext/postgres.nu` (direct libpq FFI): reads SQL from stdin one `;`-terminated statement at a time, renders result sets as aligned tables, reports command tags / `ERROR:` messages, and supports `\dt \d \l \du \conninfo \? \q` plus `-c "SQL"` one-shot mode. Connect via a conninfo arg, `$PG_CONNINFO`, or libpq's own `PG*` env defaults. | local (PostgreSQL + libpq) |
| [`pg_optional.nu`](pg_optional.nu) | PostgreSQL with the language's **option types**: binds nullable parameters with `Vec ?String` (`F` = SQL NULL) via `pg_exec_params_opt` — internally walked with `vec_get [?String]` → `??String` — and reads nullable columns back as `?String` / `?i` via `pg_get_opt` / `pg_get_opt_int`, matched with `??`. | local (PostgreSQL + libpq) |

### LLM / Anthropic API

| File | What it does | Tag |
|---|---|---|
| [`claude_chat.nu`](claude_chat.nu) | Minimal Anthropic Messages-API CLI: reads `ANTHROPIC_API_KEY`, sends prompt from argv or stdin, streams the response. | local (API key + network) |
| [`claude_agent.nu`](claude_agent.nu) | Tool-using Claude agent loop with two registered tools. Demonstrates the full tool-use cycle: model emits `tool_use` → executor runs tool → result fed back → model continues. | local (API key + network) |

### Canvas / graphics (SDL2)

These open a window via the SDL2 canvas FFI in `stdlib/canvas.c`. The
playground has no display surface; build locally with SDL2 dev libs
installed. All eight cap out at 60 fps and exit on window close.

| File | What it does | Tag |
|---|---|---|
| [`pixels_demo.nu`](pixels_demo.nu) | Minimal canvas animation: a plasma-like sinusoidal colour field, sweeping across a WxH pixel window. The "did SDL link" smoke test. | local (SDL canvas) |
| [`starfield.nu`](starfield.nu) | 3D warp-speed starfield with motion blur. | local (SDL canvas) |
| [`doomfire.nu`](doomfire.nu) | Classic Doom fire effect. | local (SDL canvas) |
| [`gameoflife.nu`](gameoflife.nu) | Conway's Life — classic two-colour, big and clear. | local (SDL canvas) |
| [`sand.nu`](sand.nu) | Interactive falling-sand simulation. Click-and-drag to drop sand. | local (SDL canvas) |
| [`primordial_canvas.nu`](primordial_canvas.nu) | Same rules as `primordial.nu` (above, in *Algorithms*) but rendered live on the pixel canvas. | local (SDL canvas) |
| [`audio_sparkles.nu`](audio_sparkles.nu) | Microphone-driven pixel fireworks — peak detection on input audio triggers visual sparkles. | local (SDL + microphone) |
| [`audio_sparcles2.nu`](audio_sparcles2.nu) | Variant of `audio_sparkles.nu` with tuned colour ramp + persistence. | local (SDL + microphone) |

## Language features at a glance

| Feature | First appearance |
|---------|-----|
| Functions (`@`) | `fizzbuzz.nu` |
| Conditionals (`?`) | `fizzbuzz.nu` |
| While loops (`~`) | `fizzbuzz.nu` |
| Mutable bindings (`: ~ T`) | `fizzbuzz.nu` |
| Structs (`: Name {}`) | `wordcount.nu` |
| Enums (`: \| Name {}`) | `calculator.nu` |
| Pattern match (`??`) | `calculator.nu` |
| Option type (`?T`) | `calculator.nu` |
| Result + try-propagate (`!T E` + `\`) | `calculator.nu` |
| Pointers (`*T`) | `calculator.nu` |
| File I/O | `wordcount.nu` |
| CLI args | `wordcount.nu` |
| Slice literal + foreach borrow | `slice_test.nu` |
| Closures + capture | `test_05_closures_and_capture.nu` |
| Generics | `find_clone.nu` (Vec[String] / regex) |
| HTTP client | `jsonrequest.nu` |
| HTTP server | `static_server.nu` |
| MCP server | `mcp_echo_server.nu` |
| Async / fibers | `async_http_server.nu` |
| Anthropic SDK | `claude_chat.nu` |
| Regex | `find_clone.nu` |
| SDL2 canvas | `pixels_demo.nu` |

## Running examples on the playground

The "playground" tag in the catalogue above marks examples that the
public WASM playground can run as-is — they read at most stdin and
argv, write to stdout / stderr, and use no network / no SDL / no
secrets. Paste the source into the editor at
[play.nurl-lang.org](https://play.nurl-lang.org), click *Run*, and the
container compiles + runs your code under wasmtime.

"local" examples need a feature the WASM sandbox does not (yet)
expose: outbound network, a listening socket, an `ANTHROPIC_API_KEY`,
a display surface for SDL, or microphone input. Build them on a host
where those are available.
