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

Add **`--gpu`** to a worker and it also advertises the **GPU capability**: it
registers the GPU wasm handler and runs those chunks with GPU host imports
live (`wt --allow-gpu`), so CUDA/NVRTC calls inside a kernel module execute on
the node's real GPU. GPU tasks are routed **only** to `--gpu` workers — a mixed
CPU/GPU cluster just works (see *GPU compute* below).

A cluster is defined and secured by **`--token`**: every node launched with the
same token forms one cluster, and nodes with different tokens are mutually
invisible even on a shared relay. The token does two things, both derived
deterministically (no coordination):

* **isolation** — it hashes into the relay multicast group id, so a node without
  the token can't even see the cluster's gossip; and
* **authenticity** — it keys an HMAC-SHA256 tag on every compute payload and
  result, so a worker only runs token-authentic jobs and a coordinator only
  accepts token-authentic results.

> **Requires NURL ≥ v0.10.12** (built from source against your installed stdlib
> at install time). **wasm kernels additionally need a `wasmtime` on each
> worker** — the toolchain's own pure-NURL runtime (`packages/wasmtime`) is a
> drop-in (put it on `PATH` as `wasmtime` or set `$WASMTIME`), so no external
> runtime is required; the Bytecode-Alliance `wasmtime` works too. `--mcp`
> auto-mints a self-signed TLS cert on first run **in pure NURL**
> (`std/x509_gen` — no `openssl`, no subprocess), or pass your own with
> `--tls-cert`/`--tls-key`.

## The control surface (what the LLM sees)

Thirteen tools, with self-describing schemas kept **deliberately short** so a
model uses them without wasting context. The depth an LLM needs beyond a
one-line schema — the CUDA-C ABI, the iterate/shuffle recipes, dataset caching,
and the honest size/support limits — lives in **`swarm_help`**, fetched one
topic at a time. Start there if unsure how a tool works.

| tool | arguments | does |
|------|-----------|------|
| `swarm_help` | `topic` (string, optional) | on-demand guidance, one topic at a time: `overview`, `workflow`, `expr`, `cuda`, `iterate`, `shuffle`, `datasets`, `gpu`, `limits`, `troubleshooting`. Omit `topic` for the index. The reference an LLM reaches for mid-task |
| `compute_submit` | `expr` (string), `lo` (int), `hi` (int), `reduce` (string, default `sum`), `dtype` (string, `int` default or `float`) | shard + run an **expression** kernel over `[lo,hi)`; returns a `task_id`. `dtype:"float"` evaluates the same kernel in **f64** (`x` is the index as a double, float literals like `0.5` allowed) |
| `compute_submit_kernel` | `source` (NURL program), `lo`, `hi`, `reduce`, `kind` (`element` default or `chunk`), `gpu` (bool) | run an **arbitrary NURL kernel given as source** — the server compiles it to wasm and runs it; for anything the expression language can't express (loops, helpers) |
| `compute_submit_cuda` | `cuda` (a `__device__ double f(long long x)` function), `lo`, `hi`, `reduce`, `params` (numbers), `dataset` | distributed **GPU** map-reduce: the model writes only the CUDA-C math; the server generates the whole kernel program and the `--gpu` workers run it on real GPUs |
| `compute_sample_cuda` | `cuda`, `lo`, `hi`, `params`, `out_file`, `dataset` | distributed GPU map that returns **every value** in order — curves, fields, tables (JSON ≤ 1024 values, base64 ≤ 65536, `out_file` beyond) |
| `compute_histogram_cuda` | `cuda` (`bin(x)` + optional `val(x)`), `lo`, `hi`, `bins`, `params`, `out_file`, `dataset` | distributed GPU **binned aggregation**: a whole distribution in one pass over billions of x |
| `compute_iterate` | `cuda` (`grad(...)`), `state`, `rounds`, `lr` **or** `update`, `acc_dim`, `params`, `epsilon`, `dataset`/`lo`/`hi` | **an iterative solver with the loop in the engine**: each round reduces a CUDA `grad()` into an accumulator, then applies a step rule — gradient descent by default (`lr`), or any fixpoint (k-means, EM, power iteration, momentum/Adam) via an `update` device function — and returns the converged `state` from one call |
| `compute_shuffle` | `map` (`key(x)`+`value(x)`), `reduce`, `dataset`/`lo`/`hi`, `params` | **group-by-key / reduce-by-key**: both the map and the per-key reduce run distributed on the GPU (each worker reduces its chunk by key — a combiner); the coordinator only merges the compact partial tables |
| `compute_upload_data` | `data_base64` or `file`, `name` | upload a **dataset** (flat f64 array) the GPU tools map over — returns a `dataset_id` + stats. The data is cut into content-addressed 1 MiB blocks that workers cache on disk, so a block travels **once** and later submits / iteration rounds over the same dataset ship only hashes (`seeded_blocks` in the task response shows how many blocks actually moved). |
| `compute_list_data` | — | every uploaded dataset: id, name, count |
| `compute_run_wasm` | `wasm_base64` (string), `lo`, `hi`, `reduce`, `gpu` (bool) | like `compute_submit_kernel` but you pass an **already-compiled** wasm module |
| `compute_list` | — | every task with status (`running`/`done`/`error`), kernel, range, reduce, result |
| `compute_result` | `task_id` (int) | one task's status and, once finished, the reduced value |

A submit returns at once with `status: running` (or `done` for tiny tasks);
the model polls `compute_result` until it is `done`. A task whose chunks
failed (module trap, missing runtime, GPU error) finishes as `status:"error"`
with a `failed_chunks` count — a failed chunk is **counted, never silently
folded as zero** into the answer. Example exchange:

```jsonc
// → compute_submit
{"expr":"x*x", "lo":1, "hi":1000000, "reduce":"sum"}
// ← {"task_id":1, "status":"running", "kernel":"x*x", "reduce":"sum", "lo":1, "hi":1000000, "chunks":12}
// → compute_result {"task_id":1}
// ← {"task_id":1, "status":"done", ..., "result":333332833333500000}
```

## The kernel language

A workload's *map* step is an expression in one variable `x`,
deliberately small and regular:

```
operators   + - * / %          (truncated division; ÷0 and %0 yield 0)
comparisons < <= > >= == !=     (yield 1 or 0)
logical     & |                 (operate on 0/1; non-zero is "true")
ternary     cond ? a : b
functions   min(a,b)  max(a,b)  abs(a)
variable    x        literals   integers or floats ("0.5")
```

The same grammar runs in one of two numeric domains, picked per task by
`dtype` (default `int`):

- **`int`** — all arithmetic is i64; `x` is the integer index. *(Unchanged: the
  integer path is byte-for-byte what it always was — `dtype:"float"` adds a
  parallel f64 evaluator, it does **not** slow integer tasks down.)*
- **`float`** — all arithmetic is f64; `x` is the integer index cast to a
  double; the result is a float. The integer range `[lo, hi)` is the same in
  both. Use it for real-valued kernels, e.g. `{"expr":"1.0/(x*x)","lo":1,
  "hi":1000000,"reduce":"sum","dtype":"float"}` ≈ π²/6.

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
| Basel sum ≈ π²/6 (`dtype:"float"`) | `1.0/(x*x)` | `sum` |

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
`~/.swarm-mcp`), `--workers N` (worker threads, default 1), `--gpu` (workers
run GPU wasm kernels — see *GPU compute*), `-v`.

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

## Datasets — data moved once, referenced by hash

A dataset uploaded with `compute_upload_data` is cut on a fixed grid into
**content-addressed 1 MiB blocks** (`blob.nu`): each block is keyed by its
BLAKE3-256, and the dataset is a manifest of those hashes. When a GPU tool
runs over a dataset, chunking is block-aligned and each compute chunk
references its blocks **by hash** (payload v4) rather than carrying the slice.
Blocks the owning worker does not yet hold are seeded first — a `kind_blob`
task with the same ring key as the compute chunk, so it lands on the same
worker — and cached to disk (`$TMPDIR/swarmb_<hex>.blob`), verified against
the hash on arrival. A worker then assembles its slice from the cache; a
missing or corrupt block fails the chunk **visibly** (`failed_chunks`), never
silently.

The payoff: N submits (or the N rounds of an iterative algorithm) over one
dataset pay the transfer **once per worker**. The task response's
`seeded_blocks` is the number of blocks that actually moved — `0` means every
block was already cached and the re-run shipped nothing but hashes.

## No single point of failure — relay failover

`--connect` takes a **list** of relays (`--connect a:47700,b:47700`). Any one
bootstraps a node; if the relay a node is on dies, the node rotates to the
next in the list and re-forms.

- **Workers** keep their identity across reconnects and run a ~2 s heartbeat;
  when it fails to send, the relay is gone, so the worker re-dials the next
  relay, re-registers and re-announces. Its on-disk block cache survives, so
  re-seeding a dataset is idempotent.
- **The coordinator** probes its relay before each submit and, if it is dead,
  rebuilds its swarm on the next reachable relay — preserving tasks, datasets
  and caches — and submits there.

Run two or more relays and none is a SPOF: kill the relay a running cluster
is on and the workers and coordinator converge on a survivor, mid-flight.

## Surviving a worker death — chunk re-dispatch

A relay is not the only thing that can fail: a **worker** can crash or trap
mid-task. For the non-dataset GPU tools (`compute_submit_cuda`,
`compute_sample_cuda`, `compute_histogram_cuda`) the coordinator no longer loses
the job — it re-dispatches the lost chunk to a surviving worker.

Each chunk is dispatched with a small **retry plan**: its (immutable, HMAC-tagged)
payload and the worker it routed to. On every poll the coordinator checks each
chunk, and one that either **traps** (a chunk result with `ok=0`) or goes
**silent past a deadline** (its worker presumed dead) is re-dispatched — to a
*different* worker, by salting the ring key until it maps to an owner other than
the one that just failed (no membership mutation, so a transient blip never
corrupts the ring). A chunk finalises only once every chunk has settled, so a
returned result still covers the whole range — now surviving a worker death
instead of erroring out. The task reports how many re-dispatches it took as
`retries`; only a chunk that fails on every worker across all attempts is
reported as a `failed_chunks` error, exactly as before.

```jsonc
// a --gpu worker is killed mid-task; its chunk is re-routed and the sum is exact
{"task_id":1, "status":"done", "result":800000000, "retries":4}
```

Not yet covered (documented in `swarm_help "limits"`): dataset-backed tasks (a
fresh worker would need the data blocks re-seeded first — resubmit to retry,
blocks stay cached) and the in-call loops `compute_iterate` / `compute_shuffle`.

## Group-by-key — the shuffle primitive

`compute_shuffle` is the building block for group-by, word-count, histograms
over arbitrary integer keys, and joins. You give a CUDA **map**:

```
__device__ long long key(long long x)   { return x % 100; }  // the group key
__device__ double    value(long long x) { return 1.0; }       // its contribution
```

and a **reduce** op (`sum` / `product` / `min` / `max` / `count`). **Both the
map and the per-key reduce run distributed on the GPU**: each worker maps its
chunk *and* reduces it by key on the device — into a compact K-slot
open-addressing hash table (a MapReduce **combiner**) — and the coordinator
only merges the small per-chunk partial tables:

```json
{ "groups": { "0": 42.0, "1": 37.0, … }, "n_groups": 100, "pairs_mapped": 1000000, "distributed_reduce": true }
```

Over a dataset the `key`/`value` functions take `double v = data[x]` and the
block cache means the input moves once. A join is two shuffles into a shared
key space, combined per key.

The O(N) per-key accumulation runs on the workers, so the coordinator never
sees the raw pairs — only the reduced tables (far less data when keys are
few). `hi - lo <= 8388608` and the result is capped at 65536 distinct keys —
narrow the range or coarsen the key for more.

## Iterative algorithms — the loop runs in the engine

`compute_iterate` runs a **fixpoint solver** without a model-in-the-loop. The
**coordinator** loops entirely on its own:

1. reduce a CUDA `grad()` into an **accumulator** vector — a distributed GPU
   vecreduce over the range/dataset with the current `state` as the runtime
   parameters,
2. apply a **step rule** to get the next `state`,
3. stop at `rounds`, or early once the largest `|state change|` falls below
   `epsilon`.

It returns the converged `state`, `rounds_run` and `converged` from **one tool
call** — the model does not run the loop message by message, which was slow and
fragile. Over a dataset the blocks are cached on the workers after round one, so
every later round ships only the `state`: `seeded_blocks` reports the blocks
moved across the *whole* run (one per block, not one per round).

**The default step rule is gradient descent.** Give a `grad()` that scatter-adds
each element's contribution and a learning rate `lr`; the engine does
`state[j] -= lr * grad[j] / N`:

```
__device__ void grad(long long x, double v, double* g, const double* p) {
    // p is the current parameter vector (== state); v = data[x]
    // fit the mean: minimise sum (theta - v)^2
    swarm_g_add(g, 0, 2.0 * (p[0] - v));
}
// state:[0], lr:0.4, dataset:id  →  converges to the mean
```

**Any other step rule is an `update` device function** — this is what turns the
engine into a general solver (k-means, EM, power iteration, PageRank,
momentum/Adam). `update` returns the new `state[j]` and reads the packed inputs
through named accessors: `swarm_state(i)`, `swarm_acc(i)` (the reduced
accumulator), `swarm_N`, `swarm_param(i)`, with `swarm_dim` / `swarm_adim` for
loops. Two things it unlocks:

- **The accumulator can be wider than the state** (`acc_dim`). A grad that
  scatters *sufficient statistics* and an update that reduces them expresses
  algorithms SGD cannot. 1-D k-means, `K=2`, is a 2-vector `state` over a
  4-wide accumulator `[sum0, sum1, count0, count1]`:

  ```
  // grad: assign each point to its nearest centroid, accumulate (sum, count)
  __device__ void grad(long long x, double v, double* g, const double* p) {
      double d0 = v-p[0]; if (d0<0) d0=-d0;
      double d1 = v-p[1]; if (d1<0) d1=-d1;
      long long c = (d0<=d1) ? 0 : 1;
      swarm_g_add(g, c, v); swarm_g_add(g, 2+c, 1.0);
  }
  // update: new centroid = sum / count
  __device__ double update(long long j, const double* p) {
      double s = swarm_acc(j), n = swarm_acc(swarm_dim + j);
      return (n > 0.0) ? (s / n) : swarm_state(j);
  }
  // state:[0,50], acc_dim:4  →  matches numpy Lloyd exactly
  ```

- **A global reduction inside a step** (a norm for power iteration, a
  renormalisation for EM) is just a loop over `swarm_acc` inside `update` —
  `swarm_adim` is small, so each thread recomputing it is free. Optimizer state
  (momentum, Adam moments) rides as extra components of `state` that `update`
  rewrites — no engine support needed.

Full ABI, more recipes, and the size bounds (`state ≤ 4096`, `acc_dim ≤ 65536`):
**`swarm_help "iterate"`**.

Two ways to get there:

- **`compute_submit_kernel`** — hand over the kernel as **NURL source**; the
  server compiles it to wasm itself, locally, via the wasmbuilder package
  (the installed toolchain's nurlc + bundled zig cc — no network). Only when
  the local toolchain can't build wasm does it fall back to POSTing to a NURL
  build service (`$NURL_BUILD_API`, default `https://play.nurl-lang.org`).
  Compile errors come straight back to the model.
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

### Chunk kernels

By default the generated program calls `kernel(x)` **per element**. Pass
`kind:"chunk"` and the kernel is `@ kernel i lo i hi → i` (or `→ f`) instead,
called **once with the worker's whole sub-range** — the kernel owns the loop
and returns the chunk partial; the reduce op still combines partials across
chunks. This is the right granularity when the kernel has per-invocation setup
cost (open a device, JIT something, allocate buffers) or wants to vectorise
the range itself — it is what the GPU path is built on.

## GPU compute

The cluster runs **real GPU workloads** end-to-end: kernels execute on each
worker's NVIDIA GPU via CUDA, JIT-compiled at run time with NVRTC — while the
work unit that travels the cluster stays an ordinary, HMAC-tagged **wasm
module**. No CUDA toolkit is needed on any node (only the driver's `libcuda` +
`libnvrtc`), and non-GPU nodes need nothing at all.

```sh
# a GPU compute node: the pure-NURL wasmtime as the runtime + --gpu
swarm-mcp --token mysecret --worker --gpu --connect <relay-host>:47700
```

The model then writes **only the math** — `compute_submit_cuda` takes a CUDA-C
map function and the server generates everything else (the NVRTC JIT harness,
a grid-stride map over the range, on-device block reduction, the host fold):

```jsonc
// → compute_submit_cuda: ∫₀¹ 4/(1+t²) dt · 1e9  =  π·1e9, on the GPUs
{"cuda": "__device__ double f(long long x) { double t = (double)x * 1e-9; return 4.0 / (1.0 + t*t); }",
 "lo": 0, "hi": 1000000000, "reduce": "sum"}
// ← {"task_id":1, "status":"done", ..., "result":3.14159e+09}
```

On an RTX 4090 one 250-million-element chunk completes in ~0.3 s **including**
process spawn and the NVRTC JIT — around three orders of magnitude faster than
the interpreted expression path on the same machine. Ranges in the billions
are practical.

### Dynamic: runtime params + module caches

`params` makes kernels **parameterised without recompiling**: pass an array of
numbers and write `f(long long x, const double* p)` — the values ride each
chunk's argv into a device buffer, never touching the generated source. The
coordinator caches compiled modules by generated-source hash and each worker
caches them by content hash, so a parameter scan pays the kernel build once
(~5–15 s) and then re-runs at interactive speed (seconds per submit):

```jsonc
{"cuda": "__device__ double f(long long x, const double* p) { return pow(sin((double)x * p[0]), p[1]); }",
 "lo": 0, "hi": 100000000, "reduce": "sum", "params": [0.001, 2.0]}
// … resubmit with "params": [0.002, 2.0], [0.001, 4.0], … — no rebuild
```

### Arrays back: sample and histogram

Two more GPU tools return **vectors**, not just one number:

* **`compute_sample_cuda`** gathers `f(x)` for every `x` in `[lo, hi)` in
  order — sample a curve, tabulate a function, render a field. Small results
  come back inline (JSON array ≤ 1024 values, base64 raw f64 LE ≤ 65536);
  bigger ones (≤ 1M values) are written to `out_file` on the MCP host.
  `min`/`max`/`mean` ride along either way.
* **`compute_histogram_cuda`** turns a full pass over the range into K bin
  sums: `bin(x)` picks the bucket, `val(x)` (default 1.0 — plain counting)
  the weight, accumulated with an on-device atomic add and combined
  elementwise across chunks. A value distribution over 10⁹ x is one call.

Under the hood the vector modes skip stdout entirely: the module writes raw
little-endian f64s to a sandbox-preopened file in one `fwrite`, the worker
validates the byte count, and the chunk result frame `[ok][count][f64…]`
carries it home over the same HMAC-tagged wire.

### Real data: datasets

`compute_upload_data` brings **your data** to the cluster — a flat numeric
array, as base64 (raw little-endian, in memory, up to 256 MiB) or a **file on
the MCP host** (up to **64 GiB**). A file is **streamed from disk**: the
coordinator hashes it block by block into the content-address manifest and never
holds the whole thing in memory, and later seeds each block straight from the
file — so a dataset's size is bounded by disk, not coordinator RAM. Big datasets
shard into worker-sized chunks automatically.

**`dtype` picks the element type** — `f64` (default), `f32`, `i32`, or `i64`.
Data is stored in its **native width** (so `f32`/`i32` halve the transfer and
GPU memory of real 32-bit data), and each element is **promoted to a `double`
on the GPU** — so your device function is always `f(long long x, double v)`
regardless of how the data is stored. The CUDA tools then take `dataset: id`:

```jsonc
// → compute_upload_data {"file": "/data/readings.f32", "dtype": "f32", "name": "sensor-a"}
// ← {"dataset_id": 1, "count": 100000, "dtype": "f32", "min": -4.27, "max": 14.54, "mean": 5.0}

// GPU variance numerator over the data, mean passed as a runtime param:
{"cuda": "__device__ double f(long long x, double v, const double* p) { double d = v - p[0]; return d * d; }",
 "dataset": 1, "reduce": "sum", "params": [5.00452]}

// pointwise transform (sample), value distribution (histogram) — same shape:
{"cuda": "__device__ long long bin(long long x, double v) { return (long long)floor(v); }",
 "dataset": 1, "bins": 10}
```

Without `lo`/`hi` the whole dataset is processed. Sharding follows the
map-reduce split rule — each chunk's payload carries exactly its own slice of
the data (capped ~12 MB per chunk, under the relay's 16 MB frame limit), so a
worker needs no separate fetch and the HMAC tag covers data and work alike.
Mean / variance / extrema / distributions / normalisations over ~10⁷-element
arrays run in a couple of seconds end to end.

How the pieces fit (each is independently reusable):

* **Capability routing.** A `--gpu` worker advertises a capability bit in its
  HELLO (a trailing byte older nodes ignore). Every node folds GPU-capable
  workers into a second, GPU-only consistent-hash ring, and the GPU task kind
  is scoped to that ring (`dist/job`'s per-kind routing rings) — ownership,
  dispatch and mid-flight re-homing all stay inside the capability domain, so
  a GPU chunk can never land on (or be forwarded to) a CPU-only worker.
* **FFI as imports.** The generated kernel program declares the CUDA/NVRTC FFI
  directly (the same ABI as `packages/gpu`); built with `--ffi-host-imports`
  those symbols become wasm `env` imports.
* **The GPU bridge.** The pure-NURL `wasmtime` resolves those imports against
  the worker's real `libcuda`/`libnvrtc` — but only under `--allow-gpu`, which
  is exactly what a `--gpu` worker passes for GPU chunks (and *only* for GPU
  chunks; plain wasm kernels keep the sealed sandbox).

`compute_submit_kernel` (with `gpu:true`, usually `kind:"chunk"`) and
`compute_run_wasm` (with `gpu:true`) expose the same machinery for hand-written
GPU kernels: any NURL source with `cuda`/`nvrtc` FFI declarations compiles to
a module whose GPU calls run on the workers' hardware.

> **Trust note:** GPU host imports pierce the wasm sandbox by design (device
> pointers are raw host handles), which is why they are per-worker opt-in
> (`--gpu`) and per-task opt-in (`gpu:true`), on top of the cluster token —
> only token-authentic tasks reach a worker at all. Turn `--gpu` on only for
> clusters whose token holders you trust, same as any compute you'd accept
> from them natively. Pick the device with `CUDA_VISIBLE_DEVICES` in the
> worker's environment (the kernel program binds device ordinal 0).

## Known limits

The envelope, stated plainly (and queryable at run time via `swarm_help
"limits"`) — these are current edges to design around, not bugs:

- **Dataset size** — an inline base64 upload is ≤ 256 MiB (held in memory); a
  **file** upload is streamed from disk and can be up to **64 GiB** (the
  coordinator keeps only the block manifest). **Element type** is `f64`
  (default), `f32`, `i32`, or `i64` via `dtype`; struct/record data must be
  encoded into one of these numeric widths yourself.
- **Shuffle** ≤ 8,388,608 input elements *and* ≤ 65,536 distinct keys per call
  (the intermediate/result bound). High-cardinality group-by must be
  partitioned or the key coarsened.
- **Sample** ≤ 1,048,576 values returned; **histogram** ≤ 1,048,576 bins.
  **Iterate** `state ≤ 4096`, `acc_dim ≤ 65,536`, `rounds ≤ 100,000`.
- **Fault tolerance:** a **relay** failure is survived (failover — workers and
  the coordinator converge on another relay mid-flight). A **worker** that dies
  or traps mid-task is **auto-redispatched** for the non-dataset GPU tools
  (`compute_submit_cuda` / `_sample_cuda` / `_histogram_cuda`): the coordinator
  re-routes the lost chunk to another worker (the task's `retries` field counts
  it) and only reports `failed_chunks` if it fails everywhere after several
  attempts. **Not yet** auto-redispatched: dataset-backed tasks (a fresh worker
  would need the blocks re-seeded — resubmit; blocks stay cached, so it is
  cheap) and the in-call loops `compute_iterate` / `compute_shuffle` (a chunk
  failure ends the call — resubmit).
- **The coordinator** (the `--mcp` node) runs the iterate/shuffle loop and
  merges partials; it is **not yet redundant** — if it dies mid-run that run is
  lost, though a fresh submit on a new coordinator is fine (worker datasets and
  caches persist).

## Tests

```sh
# kernel language (parse + eval), map-reduce + sharding (HMAC round-trip),
# and the cluster token (group isolation + HMAC auth) — ASan-clean
NURL_STDLIB=<repo> ../../nurl.sh tests/expr_test.nu  /tmp/et && /tmp/et
NURL_STDLIB=<repo> ../../nurl.sh tests/work_test.nu  /tmp/wt && /tmp/wt
NURL_STDLIB=<repo> ../../nurl.sh tests/token_test.nu /tmp/tt && /tmp/tt

# HELLO capability byte + roster, CUDA kernel generator + result frames
NURL_STDLIB=<repo> ../../nurl.sh tests/caps_test.nu       /tmp/ct && /tmp/ct
NURL_STDLIB=<repo> ../../nurl.sh tests/cudakernel_test.nu /tmp/ck && /tmp/ck

# end-to-end: an all-in-one node + MCP over HTTPS + CLI submit + token isolation
./tests/live_smoke.sh

# live GPU end-to-end (skips cleanly without an NVIDIA GPU): compute_submit_cuda
# on real hardware + mixed CPU/GPU cluster routing
./tests/gpu_smoke.sh

# live compute_iterate: gradient descent (fit the mean) and — the general
# fixpoint path — 1-D k-means, each checked against a numpy oracle
./tests/iterate_smoke.sh
./tests/general_smoke.sh

# in-computation fault tolerance (needs 2 GPUs): kill a worker mid-task and
# verify its chunk is re-dispatched so the result is still exact
./tests/faulttol_smoke.sh

# file-backed datasets bigger than coordinator RAM: upload a >256 MiB file,
# reduce it exactly, and confirm the coordinator's RSS stays far below its size
./tests/bigdata_smoke.sh

# typed datasets (needs a GPU): reduce an f32 and an i32 dataset on the GPU and
# check each sum matches numpy (accumulated in float64, as the GPU does)
./tests/typed_smoke.sh

# wasm path (needs wasmtime): compile a kernel to module.wasm, then
swarm-mcp runwasm 127.0.0.1 47700 sum 1 1000000 module.wasm --token mysecret
```

## Layout

```
src/token.nu       cluster token → group-id isolation + HMAC payload/result auth
src/expr.nu        the expression kernel language: tokenizer, parser, evaluator
src/work.nu        map-reduce: reduce ops, the expression handler, sharding
src/wasmkernel.nu  ship + run a compiled wasm kernel under wasmtime (± --allow-gpu)
src/buildwasm.nu   compile NURL source → wasm (local wasmbuilder, build-API fallback); kernel wrappers
src/cudakernel.nu  CUDA-C map fn → a complete generated GPU chunk-kernel program
src/census.nu      HELLO membership gossip (+ capability bits) → consistent-hash rings
src/main.nu        composable roles (--relay/--worker[--gpu]/--mcp) + HTTPS MCP server
```

## License

MIT OR Apache-2.0.
