# Changelog

## 0.6.5

- **`gkd_attention_masked`** — the fused attention with a per-key
  additive bias. `mask` holds `heads/hpb` rows of `nkv` floats, head `h`
  reading row `h/hpb`, added to the score before the softmax: 0 keeps a
  key, -1e30 drops it. That is how a PADDED sequence says "these
  positions are not there" — the masked key never reaches the running
  maximum and contributes exactly zero to the denominator, so every real
  row is the row it would have been unpadded. `gkd_attention` is now a
  wrapper that passes no mask, and the kernel it generates is
  character-for-character the one it always generated, so nothing
  already compiled is invalidated. First consumer: packages/embed, whose
  forward pads to a quantised length so that it stops compiling kernels
  and allocating device memory after the first few requests.
- **`gkd_attention_ok` no longer says yes to head widths the call
  rejects.** The register tile is sized for exactly `BQ*hd == 16*256`
  accumulators and the call fails closed below that, but the predicate
  only checked `hd % 16`. A caller that trusts it — map-anything sizes
  its score workspace from it — allocated nothing for the composed
  fallback and then had no workspace to fall back INTO.
- **The device-buffer pool has a budget.** Without one the table is a
  ratchet: a server whose tensor shapes follow the request retires a
  block of a size nothing asks for again, and the pool keeps it forever.
  Measured on an embedding server: 4 GB after startup, 10.8 GB after two
  hundred requests of distinct lengths, ending when the driver refuses
  and `gk_dbuf_new` dumps the whole pool and re-allocates — a stall that
  reads, from outside, as the model being unloaded and loaded again. An
  idle block that pushes the idle total over the budget now evicts the
  least recently used ones until it fits. The budget is
  `$NURL_GK_POOL_MAX` bytes, else a quarter of device memory;
  `gk_pool_budget kit bytes` sets it (0 = unlimited, the old behaviour),
  `gk_pool_idle_bytes` reports what is held. Blocks in use are never
  touched and a pool under its budget behaves exactly as before.
- **`gk_bind_thread kit → b`** (gpu 0.11.2's `gpu_bind_thread`): make
  the kit's device current on the calling thread, for anything that
  hands device work to a pool or a fiber runtime.

## 0.6.4

- Internal rename, no API change: `_gkd_ceil` and `_gkd_gemm_tiled` were
  `__`-private to `src/dev.nu` and called from `src/devops.nu`. A `__`
  name is file-scoped, so those calls went through the compiler's
  obsolete cross-file compatibility path and warned on every build. They
  now carry the single-underscore shared-internal spelling.

## 0.6.3

- **`gkd_conv2d_dil`** — atrous (dilated) 2-D convolution: tap (r,s)
  reads iy = oy·sh − ph + r·dh. The dh=dw=1 case delegates to the
  existing specialised `gkd_conv2d` kernel unchanged; the dilated body
  is a plain one-thread-per-output kernel, because dilated layers
  (U²-Net RSU4F, DeepLab heads) are a handful of small maps, not the
  hot path. First consumer: the onnx package's Conv (skyseg.onnx for
  map-anything's --mask-sky).

## 0.6.2

- `gk_mem_free` / `gk_mem_total`: free and total device memory in
  bytes, 0 when the backend cannot say (gpu 0.11.1's
  `gpu_mem_free/total`). Lets a caller cost a run before the first
  allocation instead of failing silently mid-model.

## 0.6.1

Two kernels that 0.6.0 left short of something specific, each measured.
Together they took packages/lingbot-map from 1.2x the reference to
**parity** on the same card — 138 ms a frame against its 141.

- **`gkd_attention` was reading shared memory more than it was
  multiplying.** One query by four keys is 1.25 shared reads per
  multiply-add and an SM can serve a quarter of that. Sixty-four queries
  a block instead of sixteen gives every thread a 4x4 block of the score
  tile and of the output, so four probabilities and four value channels
  feed sixteen multiply-adds: **157 us where it took 359** at a
  transformer's shape, 3.8x the composed path where it was 1.7x, and now
  ahead of the composed path at hd 128 too, where it used to lose. The
  shared budget is computed from BQ, BK, hd and the element size rather
  than guessed — getting it wrong is a launch that fails silently as a
  fail-closed F.
- **`gkd_conv2d` was computing addresses it could have folded.** Every
  loop bound and stride was a kernel argument, so a 3x3 layer paid a
  64-bit multiply-add chain per tap and the compiler could not unroll a
  window it did not know was nine taps. The twelve dimensions are
  literals in the generated source now, one compile per geometry — the
  same trick `gkd_perm` got in 0.6.0, and the same size of win: a DPT
  depth head went **39 ms -> 22 ms**. Verified bit-identical by building
  with the specialisation forced off and diffing the dump.

## 0.6.0

Performance work driven by a real model (packages/lingbot-map, a 1.16 B
parameter streaming transformer): every number below is measured on an
RTX 4090 in f32, and every kernel rewrite except `gkd_attention` is
**bit-identical** to what it replaced — the accumulation order is
unchanged, only the memory and thread shape are.

- **Shared-memory tiled GEMM / BMM on CUDA.** One thread per output
  element costs a global load of B per multiply-add, which is 4% of what
  the card can do. A 256-thread block now owns a 64x64 tile of Y, stages
  A and B through shared memory, keeps a 4x4 register tile per thread,
  and reads shared in `float4` (which also removes a 2-way bank conflict
  on every inner iteration). At 783x1024x1024: **3.1 -> 19.1 TFLOP/s**,
  and **0.6 -> 20.1** with B transposed, where the old kernel read the
  transposed operand along the wrong axis entirely. Batched matmul gets
  the same body: **3.9 -> 16.0 TFLOP/s** on 16x783x64x783.
- **`gkd_attention`** — fused scaled-dot-product attention over
  [heads, n, hd] operands, with the online softmax FlashAttention and
  torch's SDPA use. The composed form (bmm, scale, softmax, bmm) has to
  materialise a [heads, n, nkv] score matrix, which for a 72-frame
  window of 783 tokens is 2.8 GB written once and read five times; this
  writes nothing of that size. Measured against the composed path:
  Each thread owns a 4x4 block of the score tile and of the output, so
  four probabilities and four value channels feed sixteen multiply-adds
  instead of one feeding one — the difference between arithmetic and a
  shared-memory queue. **3.8x at nkv = n, 6.2x at nkv = 4n**, and 1.6x
  even at hd 128, where the composed form used to win. It is the
  ONE op here that is not bit-identical to its composed equivalent —
  the sum over keys is blocked and rescaled — and `gkd_attention_ok`
  reports in advance whether it will run, so a caller can decide
  whether it still needs to allocate the score buffer.
- **A caching device allocator.** `cuMemAlloc`/`cuMemFree` synchronise
  and cost ~315 us per 12 MB pair; a model that allocates its scratch
  per layer and per frame spent a third of every frame in the allocator
  with the device idle. `gk_dbuf_free` now retires a block for reuse by
  the next same-size `gk_dbuf_new`. Exact-size matching, because every
  `gkd_*` wrapper validates element counts exactly. `gk_pool F` disables
  it, `gk_pool_release` hands idle blocks back — which is also what an
  allocation failure does before it reports out-of-memory.
- **Per-kernel profiling.** `gk_prof`, `gk_prof_report`, `gk_prof_total`,
  `gk_prof_reset`: with profiling on, every launch is bracketed by a CUDA
  event pair and the device time accumulates into the kernel's cache
  slot. "The model is slow" is not actionable; "62% of the frame is in
  one kernel" is.
- **`gk_open_best`** opens the device a caller who does not care should
  get — `$NURL_GPU_DEVICE`, else the highest compute capability with
  memory breaking ties. `gk_open 0` binds ordinal 0, which on a box with
  an old card beside a new one is whichever the driver enumerated first.
- **`gk_dbuf_upload_raw`** uploads bytes already in the buffer's element
  type: no conversion, no staging allocation. The converting entry point
  walks every element through f64 twice, which on a 4.6 GB f32
  checkpoint is most of the load time.
- **Layernorm: a row per block** instead of a row per thread. ~800 rows
  is three blocks on a 128-SM card, and neighbouring threads walking
  their own rows coalesce nothing. The two sums stay in one thread, in
  ascending order, which is what keeps them bit-identical. **6.3x**.
- **Convolution: a 4x4 output tile per thread** (four positions along
  the row, four output channels). The old body was one multiply-add
  wrapped in four 64-bit index multiplies; now four input pixels are
  loaded once and feed four channels each. **2.2x**. Transposed
  convolution grew a fast path for stride == kernel (an exact upsample,
  what a DPT reassemble stage runs), where exactly one tap contributes
  per output and the general body was doing two 64-bit modulos per tap
  to discover that: **14.2 ms -> 0.35 ms** at 256->256, 37x21 -> 148x84.
- **A shape-specialised convolution.** Same story as the permute below:
  every loop bound and stride in `gkd_conv2d` was a kernel argument, so
  a 3x3 layer paid a 64-bit multiply-add chain per tap for an address
  the compiler could have folded, and could not unroll a window it did
  not know was nine taps. The twelve dimensions are literals in the
  generated source now (CUDA only), each geometry compiled once: a DPT
  depth head's 30 convolutions a frame went **39 ms -> 22 ms**, and the
  output is byte-identical with the specialisation forced off.
- **A shape-specialised permute.** `gkd_perm` decomposed each output
  index with a runtime loop over six 64-bit divisions and modulos and
  held its working arrays in dynamically indexed local memory, so a
  9 MB permute ran at a fourteenth of the bandwidth it should. The dims
  and the permutation are literals in the generated source now, for any
  tensor of 65 536 elements or more: **87 us -> 15 us**.
- **GEMV shape for small M.** A [1,K]x[K,N] projection ran as M*N
  threads — eight blocks for a 2048-wide output. Now one block per
  output element stages both operands coalesced into shared memory and
  keeps the dot product a single ascending sum in one thread.
- Requires **gpu ^0.11** for `gpu_timer_*`, which the profiler is built
  on. None of the above touches the CPU backend's register-tiled kernels
  from 0.5.0 — the two tilings are for different machines and coexist.

## 0.5.0

- **Register-tiled matmul/GEMM on the CPU backend — 24x.** One thread per
  output element is the right shape on a GPU, where thousands of threads
  hide the strided read of B; on the CPU backend it is the wrong shape by
  more than an order of magnitude, because `B[t*N+col]` walks a column so
  every iteration misses cache, and a scalar accumulator gives the
  vectoriser nothing. `gk_matmul_f`, `gkd_matmul`, `gkd_bmm` and `gkd_gemm`
  now emit a tiled kernel when the backend is CPU: one thread owns an 8x32
  block of C, keeps its 256 accumulators in registers, and reads B along a
  ROW — 32 contiguous elements reused by all 8 rows of the tile. Measured
  on a 6-core i7-5930K at 512x1024x1024 f64: 1.7 -> 42 GFLOP/s (610 ms ->
  41 ms). CUDA is untouched — 256 accumulators per thread is far past a
  CUDA thread's register budget and would spill to local memory.
- **Bit-identity is preserved, not merely approximately.** Each output's
  sum still runs t = 0..K ascending with the same explicit
  round-to-nearest intrinsics; only the order in which OUTPUTS are visited
  changes, and that changes no sum. Results stay bit-identical to the
  per-element kernel, to the CUDA kernel, and to a naive sequential host
  matmul — pinned by gpukit's and tensor's existing CPU-vs-numpy batteries.
- `gkd_gemm` with `transb=1` deliberately stays on the per-element kernel:
  staging a transpose at call time to reach the tiled body was measured
  and is a LOSS. Callers who want the tiled path transpose their weights
  once, at load.
- **`gkd_resize_bilinear`** — NCHW bilinear resize with both corner
  conventions (`align_corners` on and off), the resampler decoders
  actually upsample with and the one `gkd_resize_nn` is not.
- **`gk_buf_esz`** — bytes per element of a `GkBuf`, now public: the device
  pointer is byte-addressed, so anyone slicing a sub-range of a buffer
  needs it.
- Requires **gpu ^0.10.1** — the tile only reaches those numbers when the
  CPU backend compiles at `-O3 -march=native`, which is that release's
  flag ladder (and its flags-in-the-cache-key fix).

## 0.4.2

- **f64 matmul/bmm are now genuinely bit-identical to a sequential host
  loop.** `gk_matmul_f`, and the F64 instantiations of `gkd_matmul` and
  `gkd_bmm`, spell their K-accumulation with explicit `__dadd_rn/__dmul_rn`
  intrinsics. The kernels always CLAIMED bit-identity ("sums t=0..K in
  order, exactly as a host loop"), but NVRTC compiles with fmad contraction
  ON by default, so `s+=a*b` fused into FMAs and the claim was false on
  real CUDA hardware — found by the grad package's device-replay parity
  suite, where tensor_matmul's silent >=100k-flop fast path made "CPU"
  results depend on whether a GPU was present. F32 kernels are unchanged:
  their contract is true-float32 semantics (numpy/onnxruntime), which the
  verified model goldens pin. Requires gpu ^0.9.1 for the intrinsics on
  the CPU backend.

## 0.4.1

- Widen the gpu requirement to ^0.9 (shipped with the gpu 0.9.0 publish):
  device-specific CUBIN kernel cache (no driver JIT at process start) and
  pinned-staged parallel uploads for large device buffers. No API change.

## 0.4.0

Dev-layer op family — the kernel library a full CNN / transformer forward
pass needs, so tensor and onnx can share ONE set of device kernels
(tensor M5 / onnx M4b groundwork):

- **`GK_I64`** element type (`long long`) for index tensors, with exact
  `gk_dbuf_upload_i` / `gk_dbuf_download_i` host views (`Vec i`); the f64
  views convert by C truncation. The f64 upload/download paths now enforce
  their length contracts (short source pads through staging, short
  destination fails closed — no out-of-bounds host access in any case).
- **`gkd_ew_bc`** — elementwise binary with full N-D (≤6 dims) stride
  broadcast: output dims + per-input stride tables (stride 0 broadcasts a
  dim = numpy broadcasting). The wrapper proves the largest reachable
  offset fits inside each input before launching.
- **`gkd_bmm`** — batched matmul `Y[b,M,N] = A[b,M,K]·B[b,K,N]` with
  per-operand batch broadcast (a single matrix can serve every batch).
- **`gkd_gather` / `gkd_scatter`** — axis view (outer, ax, inner) with
  GK_I64 indices; negative indices wrap per ONNX, out-of-range reads give
  0 / writes are skipped (never out of bounds).
- **`src/devops.nu`** — the NN operator family, kernel bodies lifted from
  packages/onnx's proven f32 operator set and generalised over the element
  type with IDENTICAL arithmetic order (the GK_F32 instantiation is
  bit-compatible): `gkd_gemm` (alpha/beta/transB/optional bias),
  `gkd_conv2d`, `gkd_convtranspose2d`, `gkd_maxpool2d` (NCHW, batch 1),
  `gkd_batchnorm`, `gkd_leakyrelu`, `gkd_clip`, `gkd_erf`,
  `gkd_layernorm`, `gkd_softmax_ax` (interior axis), `gkd_copy_ax`,
  `gkd_slice_ax`, `gkd_perm` (N-D ≤6 transpose), `gkd_resize_nn`,
  `gkd_expandlast`, `gkd_reducel2`, `gkd_argmax` (any dtype → GK_I64),
  `gkd_eos_gather` (CLIP EOS read-out). Data-movement ops accept GK_I64;
  arithmetic ops are float-only.
- Every wrapper validates buffers, dtypes and sizes and fails closed —
  a wrong shape never reaches the device. `tests/opscheck.nu`: 57 checks
  (f32 + f64 + i64 + fail-closed guards) vs numpy on CUDA and the CPU
  backend, ASan clean.
- **`gk_autosync` / `gk_sync`** — gk_run_dev (and every gkd_* kernel)
  normally syncs the device after each launch; an executor chaining
  hundreds of launches (the onnx graph walk) can turn autosync off and
  sync once at the end. The CUDA stream serialises kernels and downloads
  synchronise implicitly, so results are unchanged.

## 0.3.1

- Manifest only: the gpu dependency range is `^0.3` (0.3.0 was published
  with `^0.2`, which is disjoint from onnx 0.5.0's `^0.3` — a resolver
  could try to install two gpu versions side by side).

## 0.3.0

Device-resident layer (`src/dev.nu`) — data stays on the GPU between ops:

- **`GkBuf`** — an element-typed device allocation (`GK_F32` | `GK_F64`)
  with `gk_dbuf_new` / `_free` / `_upload` / `_download` (f64 host vectors
  convert to/from the buffer's element type through a staging buffer).
- **`gk_run_dev`** — compile-cached launch + sync over RAW device args
  (`gk_arg_dev` + `gpu_arg_*` scalars), zero marshalling.
- **`gkd_*` kernels**, dtype-generic (float/double sources cached per
  dtype): elementwise `add/sub/mul/div` with 1-element scalar broadcast,
  unary `relu/sigmoid/exp/tanh/sqrt/log`, `matmul` (sequential-k
  accumulate), numerically-stable row `softmax`, `sum` reduction.
- **Numerics:** GK_F32 computes IN float32, accumulation included — true
  float32 semantics matching numpy float32 / onnxruntime. GK_F64 matches
  kernels.nu exactly. `tests/devcheck.nu`: 12/12 vs numpy on CUDA.

## 0.2.0

- **Breaking:** `gk_open` now returns a heap `*GpuKit` (was a by-value
  `GpuKit`), so a kit can be held as a long-lived / lazily-probed singleton
  with a persistent kernel cache; `gk_close` frees it. All `gk_*` functions
  take `*GpuKit`. Update `: GpuKit kit ( gk_open 0 )` → `: *GpuKit kit ( gk_open 0 )`.
- Added `gk_compile` — warm the cache with a kernel and report whether it
  built, so a long-lived caller can detect a bad kernel at setup rather than
  on first launch.

Both shaken out by dogfooding gpukit on the `anomaly` package's GPU path.

## 0.1.0

- Initial release: `gk_open`/`gk_close`, typed bindings (`gk_in_f`/`gk_in_i`/
  `gk_out_f`/`gk_out_i`, raw `gk_buf_in`/`gk_buf_out`, `gk_i32`/`gk_i64`/
  `gk_f32`), the `gk_run` marshalling workhorse with a per-name kernel cache,
  and ready-made f64 kernels (elementwise, map, matmul, reduce-sum, dot).
