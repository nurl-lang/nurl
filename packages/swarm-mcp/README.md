# swarm-mcp — an MCP-controlled distributed compute engine

`swarm-mcp` lets a **language model** drive a distributed compute cluster over
the [Model Context Protocol](https://modelcontextprotocol.io). The model sets a
workload — an integer **expression kernel** in the variable `x`, plus a range
and a reduce op — and the cluster evaluates it map-reduce style across every
live worker. The model submits tasks, lists running ones, and reads finished
results, all through three MCP tools.

It is built on the [`swarm`](../swarm) distributed stack: `net/relay` for reach,
`net/transport` for the pubkey seam, `dist/ring` for key ownership, and
`dist/job` for dispatch. A machine joins the cluster just by running
`swarm-mcp worker`; the MCP server is a cluster coordinator that exposes the
control surface.

> **Requires NURL ≥ v0.10.3** (the relay verbose field; built from source
> against your installed stdlib at install time).

## The control surface (what the LLM sees)

Three tools, with self-describing schemas so a model uses them without docs:

| tool | arguments | does |
|------|-----------|------|
| `compute_submit` | `expr` (string), `lo` (int), `hi` (int), `reduce` (string, default `sum`) | shard + run the kernel over `[lo,hi)`; returns a `task_id` immediately |
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

# one relay (the meeting point), one per cluster
swarm-mcp relay 0.0.0.0 47700           # add --v to log workers joining/leaving

# any number of compute nodes — joining is just running this
swarm-mcp worker <relay-host> 47700

# the MCP server (stdio) — point your LLM client at this command
swarm-mcp mcp <relay-host> 47700
```

A manual CLI submit (no MCP) is handy for testing:

```sh
swarm-mcp submit <relay-host> 47700 sum 1 1000000 'x*x'
# → sum of (x*x) over [1,1000000) = 333332833333500000
```

## How it works

1. **Join = announce.** A worker broadcasts a HELLO to the relay group
   (`census.nu`); every node folds it into the consistent-hash ring. Each worker
   registers one generic **kernel handler** (`work.nu`).
2. **Submit = shard by key.** The MCP coordinator discovers the live workers,
   splits `[lo,hi)` into chunks, and keys each so `dist/ring` routes it to its
   owner; `dist/job` carries it over the transport.
3. **Execute = interpret the kernel.** The owning worker parses the expression
   once (`expr.nu`) and folds it over its sub-range, returning a partial result
   recorded idempotently.
4. **Aggregate.** The coordinator combines the partial folds with the reduce op
   and reports the value back through the MCP tool.

The coordinator drains cluster traffic on every tool call, so tasks make
progress as the model polls — no background thread, single-process, robust.

## Roadmap

This is **phase 1**: the kernel is an interpreted integer expression — enough
for any "normal-operations" workload. **Phase 2** keeps the exact same MCP
surface but lets the model supply the kernel as **arbitrary NURL code compiled
to a wasm module** shipped to the workers, so a task can be a full program, not
just an expression.

## Tests

```sh
# kernel language (parse + eval) and map-reduce + sharding — ASan-clean
NURL_STDLIB=<repo> ../../nurl.sh tests/expr_test.nu /tmp/et && /tmp/et
NURL_STDLIB=<repo> ../../nurl.sh tests/work_test.nu /tmp/wt && /tmp/wt

# end-to-end: relay + workers + a CLI submit + a full MCP session
./tests/live_smoke.sh
```

## Layout

```
src/expr.nu     the kernel language: tokenizer, parser (flat arena), evaluator
src/work.nu     map-reduce: reduce ops, the kernel handler, sharding
src/census.nu   HELLO membership gossip → consistent-hash ring
src/main.nu     roles (relay | worker | submit | mcp) + the MCP server
```

## License

MIT OR Apache-2.0.
