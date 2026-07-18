# Changelog

## 0.14.0

**The shuffle's per-key reduce now runs distributed on the GPU (a combiner).**

Where 0.13.0 mapped on the GPU but grouped the (key, value) pairs on the
coordinator, `compute_shuffle` now reduces each chunk *by key on the device*
and the coordinator only merges the compact per-chunk partial tables — the
O(N) per-key accumulation, the part that used to bound the whole primitive on
one machine's RAM and CPU, now scales with the cluster.

- **`gpu_mode_shuffle_reduce`** — a new CUDA generator mode: a fused
  map+reduce kernel. Each thread computes `key(x)` and `value(x)` (the same
  user interface as before) and folds the value into a per-chunk **K-slot
  open-addressing hash table** (16 bytes/slot: an i64 key, an f64 value) with
  a portable double-atomic — sum/product via a CAS loop, min/max via
  fmin/fmax, count via +1. Empty slots carry an `LLONG_MIN` key sentinel and
  the reduce identity. K is a power of two ≥ 2× the distinct-key bound, so the
  table stays under half full and never probes to capacity.
- **The coordinator merges partials, not pairs.** It collects each chunk's
  compact table (≤ 16·K bytes, not 16·N) and folds every non-empty slot into
  the final group map with the op — associativity makes the split exact. The
  result gains `"distributed_reduce": true`.
- Same interface, same bounds (`hi - lo ≤ 8_388_608`, ≤ 65 536 distinct
  keys), same op set — but the reduce work is now spread across every GPU
  worker, and far less data returns to the coordinator when keys are few.
- Tests: `tests/cudakernel_test.nu` grows 15 shuffle-reduce generator checks
  (77 total, ASan clean); `tests/shuffle_smoke.sh` adds live group-by-min,
  group-by-max, and a 1000-key / 500 000-element multi-chunk merge (each
  chunk builds a partial table the coordinator combines) on top of the
  existing count and sum.

## 0.13.0

**The shuffle primitive — group-by-key / reduce-by-key.**

- **`compute_shuffle`** — the building block for group-by, word-count,
  histograms over arbitrary integer keys, and joins. You give a CUDA "map"
  (a `key(x)` and a `value(x)` device function that emit one (key, value) per
  element) and a "reduce" op (sum/product/min/max/count); the map runs
  distributed on the GPU across the workers, and the coordinator groups the
  emitted pairs by key and folds each group with the op. Returns
  `{ "groups": {key: value, …}, "n_groups", "pairs_mapped" }`. Works over a
  range or a dataset (with a dataset the block cache means the input moves
  once).
- **`gpu_mode_shuffle_map`** — a new CUDA generator mode: the kernel writes
  one (i64 key, f64 value) pair per element (16 bytes each, the key
  bit-reinterpreted into the double slot); the coordinator concatenates the
  per-chunk pair streams and groups them with a hashmap.
- The intermediate pairs are held on the coordinator, so `hi - lo <=
  8388608` and the result is capped at 65536 distinct keys — narrow the range
  or coarsen the key for more. (Pushing the per-key reduce onto distributed
  reducers is a future step; the map — the O(N) parallel work — is already
  distributed.)
- Tests: `tests/cudakernel_test.nu` grows 6 shuffle-map generator checks (62
  total, ASan clean); `tests/shuffle_smoke.sh` (live — group-by-count over
  300 k elements into 10 keys, and a group-by-sum, both exact vs the oracle).

## 0.12.0

**The relay is no longer a single point of failure.**

- **`--connect` takes a list** — `--connect h1:p1,h2:p2,…`. Any one of the
  named relays bootstraps the node.
- **Workers fail over.** A worker keeps its identity across reconnects and
  runs a ~2 s heartbeat announce; when the send fails (the relay is gone) it
  rotates to the next relay in the list, re-registers, re-joins the group and
  re-announces. Its on-disk block cache survives the switch, so re-seeding is
  idempotent.
- **The coordinator fails over lazily.** Before each submit the MCP node
  probes its relay with a heartbeat; if it is dead, it rebuilds its swarm on
  the next reachable relay (preserving tasks, datasets and caches) and
  submits there — a relay failure does not take the API down.
- Run two or more relays and no single one is a point of failure: kill the
  relay a running cluster is on and the workers and coordinator converge on a
  survivor, mid-flight.
- Test: `tests/failover_smoke.sh` (live — two relays, submit, kill the active
  relay, submit again and still get the right answer; stable across runs).

## 0.11.0

**The iteration engine — gradient descent with the loop in the coordinator,
not the language model.**

Iterative algorithms previously worked only if the model ran the loop
itself (a round per message: slow, and fragile if a message failed). Now
one `compute_iterate` call runs the whole loop.

- **`compute_iterate`** tool: given a CUDA `grad(...)` that scatter-adds each
  element's gradient into a K-dim accumulator (via the provided
  `swarm_g_add(g, j, val)`), an initial `state`, `rounds` and a learning
  rate `lr`, the coordinator repeatedly (1) computes the gradient as a
  distributed GPU vecreduce with the current parameters, (2) updates
  `state[j] -= lr*gradient[j]/N`, (3) stops at `rounds` or when the step
  falls below `epsilon`. Returns the converged `state`, `rounds_run`,
  `converged`.
- **`gpu_mode_vecreduce`** — a new CUDA generator mode: the user's `grad()`
  scatter-adds into the K-dim output via `swarm_g_add`, which is a
  portable CAS `atomicAdd` bound-checked against K. Per-chunk K-vectors
  combine elementwise (the histogram machinery), and the module (source-hash
  cached) is built ONCE — every round is just new parameters.
- The module JIT-compiles once, so an iteration is only a parameter change;
  over a **dataset** the content-addressed blocks (0.10.0) are cached after
  round one, so every later round ships only the K parameters. A run's
  `seeded_blocks` counts the blocks moved across the whole loop — one per
  block, not one per round.
- Tests: `tests/cudakernel_test.nu` grows 7 vecreduce generator checks (56
  total, ASan clean); `tests/iterate_smoke.sh` (live: fit a 3M-value
  dataset's mean by GD — converges to numpy's mean, and the data moves once
  across all rounds).

## 0.10.0

**Content-addressed datasets — data moved once, referenced by hash.**

Previously a dataset's slice rode inside every task payload, so N submits (or
the N rounds of an iterative algorithm) over the same data paid the transfer
N times. Now:

- **`src/blob.nu`** — a dataset is cut on a fixed grid into content-addressed
  **1 MiB blocks**, each keyed by its BLAKE3-256; the dataset is a manifest of
  those hashes. Workers cache blocks on disk (`$TMPDIR/swarmb_<hex>.blob`),
  verified against the hash on arrival — a corrupt or forged block is never
  written under a name it doesn't own.
- **Payload v4** (`wasm_gpu_chunk_payload_blobs`): a compute chunk references
  its blocks by hash instead of carrying the slice. The worker assembles
  `data[lo..hi)` from its cache (`gpu_chunk_assemble`); ANY missing or corrupt
  block fails the chunk **visibly** (`failed_chunks`), never silently.
- **Seeding** rides the ordinary job machinery: a `kind_blob` task with the
  SAME ring key as the compute chunk lands on the SAME worker (consistent
  hash), authenticated by the cluster HMAC token like every other payload.
  Blocks are seeded one at a time and confirmed before the compute chunks go
  out, so a block reaches its worker exactly once and re-submits ship only
  hashes.
- **`seeded_blocks`** in the task response reports how many blocks actually
  moved — `0` means the workers already held every block (a free re-run).
- Tests: `tests/blob_test.nu` (manifest determinism, cache store/append with
  corruption rejection, the HMAC seed handler, payload-v4 round-trip, slice
  assembly — 29 checks, ASan clean) and `tests/data_smoke.sh` (live: upload a
  12-block dataset, reduce it twice, assert the correct sum both times and
  `seeded_blocks` 12 then 0).

Depends on the `stdlib/net/relay.nu` `__read_exact` fix (a multi-megabyte
frame was dropped mid-read when a recv timeout was mistaken for a
disconnect) — see the toolchain CHANGELOG.

## 0.9.0 and earlier

See git history: unified node (relay/worker/mcp roles), token-HMAC auth,
distributed GPU compute over MCP (CUDA generator, sample/histogram, runtime
params), datasets over real data.
