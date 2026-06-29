# swarm-mcp — an MCP-controlled distributed compute engine

`swarm-mcp` lets a **language model** drive a distributed compute cluster over
the [Model Context Protocol](https://modelcontextprotocol.io). The model sets a
workload — an integer **expression kernel** in the variable `x`, or an arbitrary
**NURL→wasm kernel**, plus a range and a reduce op — and the cluster evaluates
it map-reduce style across every live worker. The model submits tasks, lists
running ones, and reads finished results, all through MCP tools served over
**HTTPS JSON-RPC** (the standard MCP "Streamable HTTP" transport).

It is built on the [`swarm`](../swarm) distributed stack: `net/relay` for reach,
`net/transport` for the pubkey seam, `dist/ring` for key ownership, and
`dist/job` for dispatch.

## One command, composable roles

Every node runs the **same command**; what it *does* is set by composable role
flags. Roles are not exclusive — a single node can be a relay **and** a worker
**and** the MCP server at once:

```sh
swarm-mcp --token <secret> [--relay] [--worker] [--mcp] [options]
```

| role | flag | what it does |
|------|------|--------------|
| relay | `--relay` | the rendezvous point nodes meet through (one per cluster) |
| worker | `--worker` | runs compute here — **every worker executes both expression and wasm kernels** |
| mcp | `--mcp` | serves the MCP control surface over **HTTPS JSON-RPC** |

A cluster is defined and secured by **`--token`**: every node launched with the
same token forms one cluster, and nodes with different tokens are mutually
invisible even on a shared relay. The token does two things, both derived
deterministically (no coordination):

* **isolation** — it hashes into the relay multicast group id, so a node without
  the token can't even see the cluster's gossip; and
* **authenticity** — it keys an HMAC-SHA256 tag on every compute payload and
  result, so a worker only runs token-authentic jobs and a coordinator only
  accepts token-authentic results.

> **Requires NURL ≥ v0.10.4** (built from source against your installed stdlib
> at install time). **wasm kernels additionally require `wasmtime`** on each
> worker; **`--mcp` needs `openssl`** on first run to auto-mint a self-signed
> TLS cert (or pass your own with `--tls-cert`/`--tls-key`).

## The control surface (what the LLM sees)

Five tools, with self-describing schemas so a model uses them without docs:

| tool | arguments | does |
|------|-----------|------|
| `compute_submit` | `expr` (string), `lo` (int), `hi` (int), `reduce` (string, default `sum`) | shard + run an **expression** kernel over `[lo,hi)`; returns a `task_id` |
| `compute_submit_kernel` | `source` (NURL program), `lo`, `hi`, `reduce` | run an **arbitrary NURL kernel given as source** — the server compiles it to wasm and runs it; for anything the expression language can't express (loops, helpers) |
| `compute_run_wasm` | `wasm_base64` (string), `lo`, `hi`, `reduce` | like `compute_submit_kernel` but you pass an **already-compiled** wasm module |
| `compute_list` | — | every task with status (`running`/`done`), kernel, range, reduce, result |
| `compute_result` | `task_id` (int) | one task's status and, once finished, the reduced value |

A submit returns at once with `status: running` (or `done` for tiny tasks);
the model polls `compute_result` until it is `done`. Example exchange:

```jsonc
// → compute_submit
{"expr":"x*x", "lo":1, "hi":1000000, "reduce":"sum"}
// ← {"task_id":1, "status":"running", "kernel":"x*x", "reduce":"sum", "lo":1, "hi":1000000, "chunks":12}
// → compute_result {"task_id":1}
// ← {"task_id":1, "status":"done", ..., "result":333332833333500000}
```

## The kernel language

A workload's *map* step is an integer expression in one variable `x`,
deliberately small and regular:

```
operators   + - * / %          (truncated division; ÷0 and %0 yield 0)
comparisons < <= > >= == !=     (yield 0 or 1)
logical     & |                 (operate on 0/1; non-zero is "true")
ternary     cond ? a : b
functions   min(a,b)  max(a,b)  abs(a)
variable    x        literals   integers
```

The *reduce* step folds the mapped values over the whole range:

| reduce | result |
|--------|--------|
| `sum` | Σ map(x) |
| `product` | Π map(x) |
| `min` / `max` | min / max of map(x) |
| `count` | how many x make map(x) non-zero |

Examples the model can write directly:

| goal | `expr` | `reduce` |
|------|--------|----------|
| sum of squares | `x*x` | `sum` |
| count even numbers | `x%2==0` | `count` |
| count in a sub-interval | `x>1000 & x<2000` | `count` |
| largest value of a polynomial | `x*x-7*x` | `max` |
| sum only where a condition holds | `x>100 ? x : 0` | `sum` |

Every reduce op is associative, so sharding the range across workers and
combining the partial folds is exact — the answer never depends on the worker
count.

## Quick start

```sh
nurlpkg install swarm-mcp

# An all-in-one node: relay + worker + MCP server, in one process.
# Point your LLM client at https://127.0.0.1:8443/mcp .
swarm-mcp --token mysecret --relay --worker --mcp

# Scale out: more compute nodes join the cluster by running the same command
# with the same --token, pointed at the relay. (No --relay → must --connect.)
swarm-mcp --token mysecret --worker --connect <relay-host>:47700

# A dedicated relay, or a dedicated MCP gateway, are just role subsets:
swarm-mcp --token mysecret --relay --listen 0.0.0.0:47700
swarm-mcp --token mysecret --mcp   --connect <relay-host>:47700 --mcp-listen 0.0.0.0:8443
```

Options: `--listen HOST:PORT` (relay bind, default `0.0.0.0:47700`),
`--connect HOST:PORT` (relay to join when this node has no `--relay`),
`--mcp-listen HOST:PORT` (MCP HTTPS bind, default `127.0.0.1:8443`),
`--tls-cert FILE --tls-key FILE` (PEM cert+key; default: self-signed under
`~/.swarm-mcp`), `--workers N` (worker threads, default 1), `-v`.

A manual CLI submit (no MCP) is handy for testing:

```sh
swarm-mcp submit <relay-host> 47700 sum 1 1000000 'x*x' --token mysecret
# → sum of (x*x) over [1,1000000) = 333332833333500000
```

Point an MCP client at the HTTPS endpoint (self-signed cert → trust it / `-k`):

```sh
curl -k https://127.0.0.1:8443/mcp -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"compute_submit",
       "arguments":{"expr":"x*x","lo":1,"hi":1000000,"reduce":"sum"}}}'
```

## How it works

Each enabled role runs its own event loop on its own OS thread, talking to the
rest of the cluster over the relay (loopback when the relay is co-located) — the
same topology you'd get from separate processes, presented as one command. Only
the relay drives the fiber reactor; worker and MCP roles do ordinary blocking
I/O, so heavy compute or a slow TLS handshake never stalls the relay.

1. **Join = announce.** A worker broadcasts a HELLO to the relay group
   (`census.nu`); every node folds it into the consistent-hash ring. Each worker
   registers a generic **kernel handler** and a **wasm handler** (`work.nu`,
   `wasmkernel.nu`).
2. **Submit = shard by key.** The MCP coordinator discovers the live workers,
   splits `[lo,hi)` into chunks, and keys each so `dist/ring` routes it to its
   owner; `dist/job` carries it over the transport.
3. **Execute = interpret the kernel.** The owning worker parses the expression
   once (`expr.nu`) and folds it over its sub-range, returning a partial result
   recorded idempotently.
4. **Aggregate.** The coordinator combines the partial folds with the reduce op
   and reports the value back through the MCP tool.

The coordinator drains cluster traffic on every tool call, so tasks make
progress as the model polls. Every payload and result carries an HMAC-SHA256 tag
keyed by the cluster token, verified on receipt — work is mutually authenticated
over the dumb (opaque) relay.

## Phase 2 — arbitrary NURL kernels, compiled to wasm

`compute_submit`'s expression language can't loop or call helpers. **Phase 2**
lifts that: the model writes a kernel as **ordinary NURL** and compiles it to a
`wasm32-wasi` module, which the cluster ships to the workers and runs under
`wasmtime` — exactly the same shard / run / combine pipeline, just with a real
program per element instead of an interpreted expression.

The kernel program's `main` reads `lo` and `hi` from argv, folds the kernel over
`x` in `[lo, hi)`, and prints the partial as a decimal integer. The cluster
shards the range, runs the module on each worker with its sub-range, and
combines the partials with the reduce op. Workers cache the module by content
hash, so it is written once per worker.

Two ways to get there:

- **`compute_submit_kernel`** — hand over the kernel as **NURL source**; the
  server compiles it to wasm itself by POSTing to a NURL build service
  (`$NURL_BUILD_API`, default `https://play.nurl-lang.org`), then runs it.
  Compile errors come straight back to the model. (Needs `curl` and a reachable
  build API on the host running the `--mcp` role.)
- **`compute_run_wasm`** — pass an **already-compiled** base64 module, e.g. one
  built with the `nurl_build_wasm` tool. No build service needed.

Example (either tool): a prime-counting kernel — a real trial-division loop,
impossible as an expression — over `[1, 1000000)` with `reduce: "sum"` returns
`78498` = π(10⁶), sharded across the workers.

With `compute_submit_kernel` the model writes **only the per-element kernel** —
no argv reading, no loop, no print. The server generates that boilerplate
(reading `lo`/`hi`, folding `kernel(x)` over the range with the reduce op,
printing the partial) around it:

```
@ is_prime i n → b { /* trial division */ }
@ kernel i x → i { ? ( is_prime x ) 1 0 }
// submit with reduce: "sum" → counts primes in [lo, hi)
```

```sh
# manual CLI equivalent (a pre-compiled full module):
swarm-mcp runwasm <relay-host> 47700 sum 1 1000000 prime_counter.wasm --token mysecret
# → sum (wasm kernel) over [1,1000000) = 78498
```

`compute_run_wasm` (and the `runwasm` CLI) take a **complete** module instead,
whose `main` reads `lo`/`hi` from argv and prints the partial itself — full
control, for when you compiled the module yourself.

## Tests

```sh
# kernel language (parse + eval), map-reduce + sharding (HMAC round-trip),
# and the cluster token (group isolation + HMAC auth) — ASan-clean
NURL_STDLIB=<repo> ../../nurl.sh tests/expr_test.nu  /tmp/et && /tmp/et
NURL_STDLIB=<repo> ../../nurl.sh tests/work_test.nu  /tmp/wt && /tmp/wt
NURL_STDLIB=<repo> ../../nurl.sh tests/token_test.nu /tmp/tt && /tmp/tt

# end-to-end: an all-in-one node + MCP over HTTPS + CLI submit + token isolation
./tests/live_smoke.sh

# wasm path (needs wasmtime): compile a kernel to module.wasm, then
swarm-mcp runwasm 127.0.0.1 47700 sum 1 1000000 module.wasm --token mysecret
```

## Layout

```
src/token.nu       cluster token → group-id isolation + HMAC payload/result auth
src/expr.nu        the expression kernel language: tokenizer, parser, evaluator
src/work.nu        map-reduce: reduce ops, the expression handler, sharding
src/wasmkernel.nu  ship + run a compiled wasm kernel under wasmtime
src/buildwasm.nu   compile NURL source → wasm via the NURL build API
src/census.nu      HELLO membership gossip → consistent-hash ring
src/main.nu        composable roles (--relay/--worker/--mcp) + HTTPS MCP server
```

## License

MIT OR Apache-2.0.
