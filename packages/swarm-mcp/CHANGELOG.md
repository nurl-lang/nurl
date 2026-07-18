# Changelog

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
