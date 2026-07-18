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

Ten tools, with self-describing schemas so a model uses them without docs:

| tool | arguments | does |
|------|-----------|------|
| `compute_submit` | `expr` (string), `lo` (int), `hi` (int), `reduce` (string, default `sum`), `dtype` (string, `int` default or `float`) | shard + run an **expression** kernel over `[lo,hi)`; returns a `task_id`. `dtype:"float"` evaluates the same kernel in **f64** (`x` is the index as a double, float literals like `0.5` allowed) |
| `compute_submit_kernel` | `source` (NURL program), `lo`, `hi`, `reduce`, `kind` (`element` default or `chunk`), `gpu` (bool) | run an **arbitrary NURL kernel given as source** — the server compiles it to wasm and runs it; for anything the expression language can't express (loops, helpers) |
| `compute_submit_cuda` | `cuda` (a `__device__ double f(long long x)` function), `lo`, `hi`, `reduce`, `params` (numbers), `dataset` | distributed **GPU** map-reduce: the model writes only the CUDA-C math; the server generates the whole kernel program and the `--gpu` workers run it on real GPUs |
| `compute_sample_cuda` | `cuda`, `lo`, `hi`, `params`, `out_file`, `dataset` | distributed GPU map that returns **every value** in order — curves, fields, tables (JSON ≤ 1024 values, base64 ≤ 65536, `out_file` beyond) |
| `compute_histogram_cuda` | `cuda` (`bin(x)` + optional `val(x)`), `lo`, `hi`, `bins`, `params`, `out_file`, `dataset` | distributed GPU **binned aggregation**: a whole distribution in one pass over billions of x |
| `compute_iterate` | `cuda` (`grad(...)`), `state`, `rounds`, `lr`, `epsilon`, `dataset`/`lo`/`hi` | **gradient descent with the loop in the engine**: each round computes the gradient as a distributed GPU vecreduce with the current parameters and updates them — returns the converged `state` from one call |
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

## Iterative algorithms — the loop runs in the engine

`compute_iterate` runs **gradient descent** without a model-in-the-loop.
You give a CUDA gradient function that scatter-adds each element's
contribution into a K-dim vector:

```
__device__ void grad(long long x, double v, double* g, const double* p) {
    // p is the current parameter vector (== state); v = data[x]
    // fit the mean: minimise sum (theta - v)^2
    swarm_g_add(g, 0, 2.0 * (p[0] - v));
}
```

plus an initial `state` (the K-dim parameter vector), `rounds`, and a
learning rate `lr`. The **coordinator** then loops, entirely on its own:

1. compute the gradient `g` as a distributed GPU **vecreduce** over the
   range/dataset with the current `state` as the runtime parameters,
2. update `state[j] -= lr * g[j] / N`,
3. stop at `rounds`, or early once the largest step falls below `epsilon`.

It returns the converged `state`, `rounds_run` and `converged` from **one
tool call** — the model does not run the loop message by message, which
was slow and fragile. Over a dataset the blocks are cached on the workers
after round one, so every later round ships only the K parameters:
`seeded_blocks` reports the blocks moved across the *whole* run (one per
block, not one per round).

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

`compute_upload_data` brings **your data** to the cluster — a flat f64 array,
as base64 (raw little-endian) or a file on the MCP host, up to 256 MiB. The
CUDA tools then take `dataset: id`, and the device functions receive each
element as a second argument:

```jsonc
// → compute_upload_data {"file": "/data/readings.bin", "name": "sensor-a"}
// ← {"dataset_id": 1, "count": 100000, "min": -4.27, "max": 14.54, "mean": 5.0}

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
