# Changelog

## 0.26.0

**The pins follow the runtime onto a wasm that has threads and sockets.**
`wasmtime ^0.14.0` and `wasmbuilder ^0.2.0` are what the v0.50.0 toolchain
released: a module can now declare a shared memory, spawn threads through
`wasi.thread-spawn` and open real sockets through the `nurl_net` host
imports (off by default, `--allow-net` enables them). For a worker running
CPU wasm chunks in-process that is not a new interface — the engine is the
same `interp_capture` call — but it is a strictly larger set of kernels that
can run: one that sleeps, one that uses `errno`, one built `--threads`, one
that talks to the network. The line these pins left behind could not run any
of them.

It also carries the fix underneath all of that: the interpreter's fast path
for stores narrower than eight bytes was a 64-bit read-modify-write, which
is exact on one thread and loses a neighbour's byte on a shared memory. A
worker never hit it — it had no second thread — but a swarm-mcp compiled to
one wasm module and run as relay + workers + MCP inside a single instance
did, as a wild pointer in the guest's own `free`.

No source change here beyond the pins and the version: the caret is at the
minor, so this is the release that lets an installed swarm-mcp resolve them
at all.

## 0.25.1

**0.25.0 shipped announcing itself as 0.24.0.** `sm_version` is a
hand-written literal and the 0.25.0 release bumped the manifest without it,
so `initialize`, `server/discover` and `--version` all reported a version
that was never published. Fixed here, and — more to the point —
`tools/check_package_version_strings.sh` now reads that spelling, so the
next release cannot repeat it. (0.31.1 of the toolchain fixed this same
drift once before by unifying three literals onto one `sm_version`; that
addressed the symptom, not the fact that nothing checked the survivor.)

The dependency pin follows the pure-NURL runtime to `wasmtime ^0.11.0`,
which is 3.1x faster over the wasm benchmark corpus and 7.5x on start-up
than the 0.9.0 line 0.25.0 was pinned to — a worker's wasm chunks get all
of it with no change here.

## 0.25.0

**Workers run wasm in-process — and therefore inside a unikernel.** The
pure-NURL wasmtime is now a package dependency (`deps/wasmtime`) and the
default engine for CPU wasm chunks: the worker decodes the chunk's bytes and
runs `_start` under `interp_capture`, with no runtime on PATH, no subprocess,
no writable filesystem and no disk cache. That is what lets the swarm-mcp
appliance boot as a NURL unikernel guest (a machine with no processes) and
still execute compiled kernels — verified end to end: a guest worker joins a
host relay over virtio-net, runs both an expression task and a wasm-kernel
task, and the reduce comes back exact (`unikernel/tests/swarm_gate.sh` gates
it in CI, cold-start-to-first-answer measured).

- `$WASMTIME` still selects an external runtime over the unchanged CLI
  contract (`wasmtime run <module> <lo> <hi>`); GPU chunks always use the
  external contract and `--gpu` still requires it.
- `wasmtime_probe` answers without spawning anything when the engine is
  in-process, so a worker's preflight no longer needs processes at all.
- Fixed two error-path leaks: both stderr-capture sites bound and freed the
  intermediate `string_trim` argument instead of leaking it per failed chunk.

## 0.24.0

**Everything an agent-experience pass found, fixed.** A full run against the
installed 0.22.0 package (report in `AX_REPORT.md`) turned up one dead surface
and a set of ways the server could mislead the model driving it. All of them
are closed here.

- **The GPU tool family works again.** Every CUDA tool failed to build its
  kernel, because wasmbuilder emitted a named vararg parameter
  (`... %a2`) in a libc shim, which is not legal LLVM — so any module whose IR
  declares `open`/`fcntl`/`printf` failed to link. Fixed in
  `packages/wasmbuilder` (`__wb_ir_decl_params` drops the `...` marker);
  verified end to end on real hardware: π·10⁸ in 3.5 s, sample, histogram,
  dataset reduce, `compute_iterate`, `compute_shuffle`.
- **A failed chunk now says WHY.** Workers append their reason (a wasm trap,
  a missing runtime, a CUDA error, a failed HMAC check) to the result frame,
  and the task reports it as `"error": "…"` next to `failed_chunks`. The
  suffix is appended after the existing frame, so mixed-version clusters are
  unaffected.
- **An unknown `reduce` is an error,** not a silent `sum`. `{"reduce":"avg"}`
  used to return a plausible wrong number with `"reduce":"sum"` echoed back.
- **A dead worker leaves the cluster.** Roster members carry a liveness stamp
  refreshed by the ~2 s HELLO heartbeat; one silent past 90 s is evicted from
  the roster and both rings. Before this a killed worker stayed in the ring
  forever and *every* later submit paid a full round of re-dispatches around
  a node that was never coming back. Eviction is self-healing: a worker that
  returns re-announces and rejoins.
- **Expression and CPU-wasm tasks are fault-tolerant too.** They now carry the
  same retry plan the GPU tools had, so a worker that dies mid-task no longer
  leaves the task `running` forever (an agent's infinite poll loop). Their
  liveness test is roster eviction rather than a fixed deadline — a legitimate
  multi-minute chunk is not mistaken for a dead node — with a 30 min backstop.
  A task whose ring runs empty finishes as an honest error instead of retrying
  into the void.
- **Liveness is aged on EVERY node, not just the coordinator.** `dist/job`
  forwards a job whose key a node does not own to whoever *its* ring says owns
  it, so a worker still holding a dead peer bounced re-dispatched chunks
  straight back into the void — a task submitted while a dead worker was still
  in the ring could never finish. Workers now expire members on the same
  heartbeat tick (never themselves: a node hears no HELLO of its own).
- **New tool `swarm_status`** — the cluster as the coordinator sees it: worker
  count, which are GPU-capable, how long since each was last heard from, task
  and dataset counts, and the liveness TTL. "No workers found" and a task that
  keeps retrying were previously unreasonable-about from the outside.
- **A long expression chunk keeps its worker visibly alive**: the fold calls a
  keepalive every few million elements, so a busy worker still heartbeats
  (its handler runs inside the pump loop).
- **The build-service fallback is honest.** The local build error is no longer
  discarded: it is logged, it leads the message when both paths fail, and the
  fallback itself is announced (it ships kernel source to a third-party host).
  The request is capped at 90 s — a hung service used to block one MCP call
  for 300 s and then report "could not reach the build API", which was wrong.
- **A role that cannot start is fatal.** A relay or MCP listener that fails to
  bind used to leave the process running with the surviving roles, so a
  duplicate instance looked alive while serving nothing.
- **`--worker` preflights its wasm runtime** at startup: `--gpu` refuses to
  start without a runtime that has `--allow-gpu`, and a CPU worker warns. This
  used to surface only as an unexplained `failed_chunks` on a later task.
- **The MCP endpoint is `/mcp`.** Any other path answers 404 instead of
  serving the same body everywhere; the SSE ready event no longer claims to be
  a different server (`nurl-mcp`).
- New offline test `tests/liveness_test.nu` covers the liveness stamp,
  eviction from roster and ring, the self-exemption, rejoining, and the
  failed-chunk reason suffix (ASan/LSan clean).
- Smaller: the startup banner is flushed (a redirected `-v` log stayed empty),
  and the dev CLI prints its summary on one line again.

## 0.23.0

**MCP tasks: the compute_submit family now speaks
`io.modelcontextprotocol/tasks`.** The submit tools were already a task API
expressed in tool arguments — submit, get a `task_id`, poll `compute_result`.
That same flow is now available in the PROTOCOL, so a task-capable client
drives a distributed reduction with no swarm-specific tool knowledge at all.

- `server/discover` declares `capabilities.extensions`
  `{"io.modelcontextprotocol/tasks": {}}`.
- A client that declares the extension on a `tools/call` for
  `compute_submit`, `compute_submit_kernel`, `compute_submit_cuda`,
  `compute_sample_cuda`, `compute_histogram_cuda` or `compute_run_wasm` gets a
  **`CreateTaskResult`** (`resultType: "task"`, 32-hex `taskId`, `ttlMs`,
  `pollIntervalMs`) instead of the tool result, and polls **`tasks/get`** until
  the task reaches `completed`. The completed task inlines exactly the
  `CallToolResult` `compute_result` would have returned, so both polling
  styles see identical payloads.
- `tasks/cancel` and `tasks/update` are served too. Cancellation is
  cooperative per the spec — the ack is guaranteed, a transition to
  `cancelled` is not (a swarm task in flight runs to completion).
- Task creation is **server-directed and per-request**: a client that does not
  declare the extension gets exactly the previous behaviour, and a call that
  registers no swarm task (an argument error, an empty cluster, a
  non-eligible tool like `swarm_help`) is never augmented.
- A non-declaring client issuing `tasks/*` gets **−32003** with
  `data.requiredCapabilities`; an unknown or expired `taskId` gets **−32602**.
  Task handles carry a 1 h TTL and are swept on access.

Covered end-to-end by `tests/tasks_smoke.sh` (CPU only — no GPU needed).
The protocol machinery lives in the toolchain's `stdlib/ext/mcp_tasks.nu`;
this package only decides which calls become tasks and how a swarm task's
state maps onto a task status.

## 0.22.0

**Dual-era MCP — the 2026-07-28 stateless revision, without dropping legacy
clients.** The MCP spec's 2026-07-28 revision removed the `initialize`
handshake in favor of per-request `_meta` and made `server/discover`
mandatory. The `--mcp` endpoint now serves both eras:

- **`server/discover`** answers with supported protocol versions (2026-07-28
  down to 2024-11-05), capabilities, server identity, and LLM-facing
  instructions pointing at `swarm_help`.
- A request declaring an unsupported `_meta` protocolVersion gets the
  spec-shaped **`UnsupportedProtocolVersionError` (−32022)** with
  `data.supported`, so a modern client can retry on a mutual revision.
- Results for modern requests carry `_meta` serverInfo; every result now
  carries `resultType: "complete"` and `tools/list` the required
  CacheableResult fields (`ttlMs`, `cacheScope`) — via the stdlib MCP
  envelope layer.
- `initialize` still works exactly as before for legacy clients, and now
  **echoes the client's requested handshake-era revision** when supported
  instead of always pinning the newest one.

**The handshake no longer lies about the version.** `serverInfo.version` was a
hand-written `0.20.0` while the package was at 0.21.1. The handshake,
`server/discover`, and the `--version` banner now all read one `sm_version`
source.

Requires a toolchain whose stdlib ships the dual-era MCP layer (NURL >
0.31.1).

## 0.21.1

**`--version` prints the version instead of failing the role check.** `swarm-mcp
--version` used to fall through to the node launcher, which rejected it with
`pick at least one role` (exit 1) plus the whole usage text. It now prints
`swarm-mcp 0.21.1` and exits 0, like every other toolchain program. `-v` is
unchanged — it stays `--verbose` — so the version flag is long-form only. The
flag is recognised anywhere on the command line, and `--help` now lists it.

**`tests/blob_test.nu` compiles again.** Its three
`wasm_gpu_chunk_payload_blobs` calls still passed the pre-`dtype` argument
list, so `hashes` and `wasm` landed one slot to the left — the v4 payload
gained a `dtype` field and the test was not updated with it. The calls now pass
`dtype` (1 = f64), and the v4 round-trip asserts it decodes back.

## 0.20.0

**Coordinator crash-restart recovery — datasets persist across a coordinator
restart.** The `--mcp` node held the dataset registry only in RAM, so a crash
lost it even though the workers still cached the blocks; the coordinator was a
single point of failure for datasets.

- Each dataset is **persisted to `$HOME/.swarm-mcp/datasets/`** on upload: a
  small `meta` (id, dtype, byte count, a pointer to the bytes, name), a
  `manifest` of the block hashes, and — for a base64 upload — a `.data` copy of
  the bytes (a file upload just records the original path). Persist failures are
  non-fatal (the dataset still works in memory this session).
- On startup the coordinator **reloads every persisted dataset** (`recovered N
  dataset(s) from disk`), so after a crash + restart the registry is intact and
  a resubmit **re-seeds the blocks from the persisted bytes** — the workers'
  cached blocks are confirmed by hash, not recomputed, so recovery is cheap.
- This is not hot standby: an iterate/shuffle call that was *in flight* when the
  coordinator died must be resubmitted. But the datasets, and the ability to
  resume, survive the restart — the coordinator SPOF is now a restart, not a
  data-loss.
- Tests: new `tests/persist_smoke.sh` uploads a dataset, **SIGKILLs the node**,
  restarts it with the same `$HOME`, and checks the dataset is recovered (count
  + name) and a GPU reduce over it is still exact (blocks re-seeded from the
  persisted copy). `gpu_smoke` / `data_smoke` (which also persist now) unchanged
  and green.

**compute_iterate retries a transient round failure in place.** A round is
idempotent (the gradient is a pure function of the current state; the update only
overwrites state on success), so a failed round is re-run a few times before the
call gives up — a GPU hiccup, a briefly-overloaded worker, or a dropped frame no
longer throws away a whole multi-round GD/fixpoint run. (A permanently-dead
worker on a dataset round still needs a resubmit; `compute_shuffle` likewise.)
`iterate_smoke` / `general_smoke` unchanged and green.

## 0.19.0

**compute_shuffle: cardinality that scales with the cluster, a 16× larger input,
and a silent-drop bug fixed.** The old caps (8.4 M elements, 65 536 keys) blocked
real high-cardinality group-by.

- **Overflow detection (correctness fix).** Each chunk reduces its keys into an
  open-addressing GPU hash table; if the table filled, keys were **silently
  dropped** and the result was quietly wrong. The kernel now counts probe
  exhaustions into a dedicated control slot, and the coordinator **rejects** a
  run whose any chunk overflowed — never a silent drop.
- **Cardinality scales with the chunk count.** The distinct-key limit is now
  **per chunk** (~131072, the size of the table a chunk ships back in one relay
  frame — the ~2 MiB frame ceiling, the same reason datasets travel in 1 MiB
  blocks), so TOTAL cardinality is that times the chunk count (~2 per GPU
  worker): hundreds of thousands of keys on one GPU, into the millions across a
  cluster. (Verified: 200 000 distinct keys on a single GPU, up from 65 536.)
- **`out_file` for large group tables.** Past 8192 groups the table can't ride a
  text result, so it is written to `out_file` as raw little-endian `(i64 key,
  f64 value)` pairs and the result carries `{n_groups, saved_to}`.
- **Input range 8 388 608 → 134 217 728 (128 M).** The coordinator only merges
  compact per-chunk tables (not raw pairs), so the row count is no longer the
  bottleneck — high-VOLUME group-by (many rows, moderate cardinality) now works.
- Tests: `tests/cudakernel_test.nu` gains overflow-counter generator checks (96
  total); new `tests/shuffle_bigkeys_smoke.sh` covers a 10 M-row group-by, a
  200 000-key result via `out_file` (parsed and verified), and rejection of a
  chunk that overflows its table. `tests/shuffle_smoke.sh` unchanged and green.

## 0.18.0

**Typed datasets — f32 / i32 / i64, not just f64.** Real data is usually 32-bit;
storing it natively halves the transfer and GPU memory of the f64-everything path.

- `compute_upload_data` takes a **`dtype`**: `"f64"` (default), `"f32"`, `"i32"`,
  or `"i64"`. The data is stored and shipped in its **native width**, and each
  element is **promoted to a `double` on the GPU** — so the kernel is always
  `f(long long x, double v)` regardless of storage. The upload reports the
  `dtype` and a `count` scaled by the element size.
- The whole dataset path is now element-size aware: block↔element mapping, the
  content-address grid, size-aware sharding, min/max/mean, and the range checks
  all scale by the storage width (an element never straddles a 1 MiB block, since
  4 and 8 both divide 1 MiB).
- The generated GPU kernel declares the input buffer in its native type
  (`const float*` / `const int*` / `const long long*` / `const double*`) and
  casts each load to `double`; the chunk payload carries the dtype (packed into
  the mode byte's high nibble, so the wire format and the f64 default are
  unchanged), and the worker reads its slice at the right stride.
- Tests: `tests/cudakernel_test.nu` gains f32/i32/i64 generator checks (94
  total); new `tests/typed_smoke.sh` reduces a **3 M-element f32 dataset** and an
  **i32 dataset** live on the GPU and checks each sum against numpy (accumulated
  in float64, as the GPU does). The f64 smokes (`gpu_smoke`, `data_smoke`,
  `iterate`, `general`) are unchanged and green.

## 0.17.0

**Datasets far larger than coordinator RAM — streamed from disk (up to 64 GiB).**

A dataset was capped at 256 MiB because `compute_upload_data` held the whole
thing in the coordinator's memory. Yet the transfer/cache unit is already a
content-addressed 1 MiB block, so holding the raw bytes was never necessary.

- **File uploads now stream.** A `{"file": …}` upload is hashed block by block
  straight from disk into the content-address manifest (min/max/mean computed in
  the same one pass), and later block seeds are read from the file on demand. The
  coordinator retains only the manifest (32 bytes/block), never the data — so a
  dataset is bounded by disk, not RAM. The cap rises from 256 MiB to **64 GiB**
  for file uploads (base64 uploads stay 256 MiB, since those bytes ride the
  request into memory). The result reports `file_backed: true`.
- **Size-aware sharding.** A chunk's data is assembled in a worker's RAM and
  uploaded to its GPU, so the chunk count now grows with the dataset (chunk bytes
  capped at 256 MiB) — a multi-GB dataset shards into worker-sized pieces instead
  of a few multi-GB chunks no GPU could hold.

**Fixed a precision bug in result serialization (affected any large float).**

While verifying the above, large reduce results came back subtly wrong — e.g. a
sum of 41,943,040 reported as 41,943,000. Root cause: the runtime's
`nurl_str_float` formats with `"%g"` (6 significant digits), silently truncating
any float past ~1e6. This hit every float result, not just datasets. Results are
now rendered **exactly** for integer-valued numbers (formatted via i64), so
reduce/count sums are precise; genuinely fractional values still use `%g` for
now (the deeper fix — a round-trip `nurl_str_float` — belongs in the runtime and
is tracked separately). `gpu_smoke.sh`'s assertions were updated from the old
lossy strings to the exact values.

- Tests: new `tests/bigdata_smoke.sh` (needs a GPU) uploads a **320 MiB file**
  (over the old cap), reduces it to the exact sum, and asserts the coordinator's
  **peak RSS stays far below the file size** (proving it streams — measured ~181
  MiB for a 320 MiB file). All existing smokes (`gpu_smoke`, `iterate`,
  `general`, `faulttol`, `data`) remain green; offline generator 87/0.

## 0.16.0

**In-computation fault tolerance: a worker death mid-task no longer loses the job.**

Until now a failed chunk was reported honestly (`failed_chunks`, never a silent
zero) but never retried — one worker crashing mid-task errored the whole job.
The non-dataset GPU tools (`compute_submit_cuda`, `compute_sample_cuda`,
`compute_histogram_cuda`) now **auto-re-dispatch** a lost chunk to a surviving
worker.

- **Per-chunk retry plan.** Each chunk is dispatched with its immutable,
  HMAC-tagged payload and the worker it routed to. On every poll the coordinator
  advances each chunk: one that **traps** (`ok=0`) or goes **silent past a
  deadline** (its worker presumed dead) is re-dispatched while it has attempts
  left; a chunk finalises only once every chunk has settled, so a returned
  result still covers the whole range.
- **Steer around the failed worker, no membership mutation.** The re-dispatch
  salts the ring key until it maps to an owner *other* than the one that just
  failed — so a transient blip never corrupts the ring, and there is no reliance
  on death-detection gossip.
  - Fixes a subtle hazard found while building this: the ring hash (FNV-1a) has
    poor avalanche on trailing key bytes, so a naive `[idx][salt]` key left
    consecutive salts on the same ring arc and the steer could never escape the
    failed owner. Keys now fold idx and salt through a splitmix-style bit mixer,
    so every attempt lands at a well-separated ring point.
- **Observable.** The task reports `retries` (re-dispatches performed); only a
  chunk that fails on every worker across all attempts is reported as a
  `failed_chunks` error, exactly as before. `swarm_help "limits"` and
  `"troubleshooting"` document the new behaviour and what it does *not* yet cover
  (dataset-backed tasks need block re-seeding on a fresh worker; the in-call
  `compute_iterate` / `compute_shuffle` loops end the call on a chunk failure —
  resubmit).
- Tests: new `tests/faulttol_smoke.sh` (needs 2 GPUs) submits a GPU reduce whose
  exact answer is known, **kills a worker mid-task**, and asserts the result is
  still exact with `retries > 0` and `failed_chunks == 0`. The happy path
  (`gpu_smoke.sh`) and the in-call tools (`iterate_smoke.sh`,
  `general_smoke.sh`) are unchanged and green.

## 0.15.0

**`compute_iterate` is now a general fixpoint solver, not just gradient descent.**

The iteration engine already ran the whole loop in the coordinator — distributed
accumulate, block-cached data, convergence — but the *step rule* was hardcoded to
`state[j] -= lr*grad[j]/N`, and the accumulator was forced to be the same width as
the state. That made it a one-trick gradient-descent tool: k-means, EM, power
iteration, PageRank, or any optimizer with its own state (momentum, Adam) had no
native path. Two changes lift that ceiling, without a workaround and without
breaking the existing SGD path:

- **A pluggable `update` device function.** Provide
  `__device__ double update(long long j, const double* p)` returning the new
  `state[j]`, and it replaces the built-in SGD step. Inside it, named accessors
  read the packed inputs — `swarm_state(i)`, `swarm_acc(i)` (the reduced
  accumulator from `grad()`), `swarm_N`, `swarm_param(i)`, with `swarm_dim` and
  `swarm_adim` for loops (a norm or per-group reduce over the accumulator). It
  runs as a tiny GPU pass over `[0, S)` each round, reusing the sample mode — so a
  global reduction like a normalization is just a loop over `swarm_acc` inside
  `update`. Omit it and the default `lr`-driven SGD step is unchanged.
- **The accumulator dimension is decoupled from the state.** `acc_dim` (default:
  the state length) sizes the vector `grad()` scatters into, so a 2-centroid
  k-means can reduce into a 4-wide `[sum0, sum1, count0, count1]` accumulator and
  the update reads `sum/count`. Optimizer state (momentum, Adam moments) rides
  inside `state` and the update rewrites it — no engine support needed.
- **Constant runtime `params`.** An optional array, the same every round,
  readable by `grad()` at `p[state_len..]` and by `update()` via `swarm_param(i)`
  — a learning rate for a custom step, a damping factor, a small fixed matrix.
- `lr` is no longer required (only in the default SGD mode); `state` and the
  result stay indexed by the state length `S`. Fully backward compatible: an
  existing `{cuda, state, lr, ...}` call runs the identical SGD loop.
- Tests: `tests/cudakernel_test.nu` grows 10 update-kernel generator checks (87
  total); new `tests/general_smoke.sh` fits **1D k-means live on the GPU** (a
  4-wide accumulator, `sum/count` update) and matches a faithful numpy Lloyd
  oracle over the identical data. `tests/iterate_smoke.sh` (the SGD path) is
  unchanged and still green.

**A `swarm_help` tool, and a leaner tool surface.**

- **`swarm_help`** — on-demand, topic-queryable guidance so the model can learn
  the parts an LLM won't infer from a one-line schema: `overview`, `workflow`,
  `expr`, `cuda` (the shared device-function ABI), `iterate`, `shuffle`,
  `datasets`, `gpu`, `limits`, and `troubleshooting`. Omit the topic for the
  index. The `limits` topic states the honest envelope (dataset ≤ 256 MiB and
  f64-only, shuffle ≤ 65 536 keys, no worker-level chunk redispatch, the
  single-coordinator run) so a caller designs around the edges instead of
  hitting them blind.
- **The tool schemas are now deliberately short**, deferring depth to
  `swarm_help`: `tools/list` dropped from ~5.7k to ~3.9k tokens (−31%) *with the
  new help tool included* — each tool still carries its signature, an example,
  and a pointer to the relevant help topic.
- Doc fix: the dataset block size is **1 MiB** (it always was, in code); several
  comments and the `compute_upload_data` description that said "8 MiB" are
  corrected. `serverInfo.version` now reports the package version.

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
