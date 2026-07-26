# Changelog

## 0.8.2

- Requirements widened to gpu `^0.11` / gpukit `^0.6`. No source change.

## 0.8.1

**Mixed precision — `gput_capture_dt(..., 2)` (Phase 3, piece 2).** A third
capture dtype: **f32 storage, f64 accumulation.** Every device buffer
(val / grad / optimizer moment) is f32 — exactly halving VRAM like pure
f32 (dtype 1) — but the arithmetic is untouched: accumulator locals stay
`double` and every op stays a `__d*_rn` f64 intrinsic (a float loaded from
a buffer promotes to double for the math and narrows on store). So a
matmul dot over K, a reduction over N, the global-norm over every
parameter, and the Adam update all accumulate in f64 while storing f32 —
killing the matmul-K swamping and clip-norm degeneracy that pure f32
suffers at scale, at zero extra memory.

Implemented as a targeted source substitution (`double*` → `float*` on
the buffer pointers only; the C style writes pointers `double*` and locals
`double `, so it is a pure text transform — no hand-authored kernels).
Kernel names carry a `gpm_` prefix; `gput_capture_dt`'s signature is
unchanged (dtype 2 is a new accepted value).

Measured (`gput_mixed_test`, RTX 4090 + CPU backend, wide AE, 80 steps),
worst parameter drift vs the f64 reference:

    pure f32 (dtype 1)   6.2e-4
    mixed    (dtype 2)   1.8e-5     (~35x closer, identical VRAM)

Pure f32 stays for short/small runs; mixed is the preferred path at scale.
(A follow-up can keep the Adam moments in f64 *storage* too — mixed
already accumulates the update in f64, but the m/v state is f32-stored,
the one remaining precision gap at extreme step counts.) Additive; the
f64 (dtype 0) and pure-f32 (dtype 1) paths are byte-unchanged
(gput_parity / gput_f32 / gpfuse tests green). Version 0.8.0 -> 0.8.1.

## 0.8.0

**`tape_drop_consts` — reclaim host RAM after a device capture (Phase 3,
piece 1).** A finetune holds its frozen base weights TWICE in f64 on the
host: once in the caller's model and again on the tape as `gop_const`
nodes. After `gput_capture` uploads every const to the device, the tape's
const value tensors are dead weight — device replay reads device buffers,
param sync-back touches only `gop_param` nodes, and `gput_set_input`
uploads freshly-recomputed rows straight to the device. `tape_drop_consts`
frees those const value tensors (null-safe: `tape_free`/`tape_reset_to`
re-read through the same guarded idiom), reclaiming the single largest
host allocation in a finetune.

Device `--f32` already halved VRAM; this attacks the HOST-RAM wall that
gates whether a large model's graph can even be built (peak host was ~2×
model-in-f64 — 0.5B ≈ 7 GB before activations). Only valid after a
successful device capture (the CPU tape can no longer forward/backward
once its const values are gone).

Verified: `drop_consts_test` (params + gradients survive, idempotent,
clean teardown) and `nurllama finetune_test` on SmolLM-135M — 17/17
byte-identical (CE 2.7488 → 4.38e-6, merged model 12/12), so freeing the
base does not perturb training. Version 0.7.0 -> 0.8.0.

## 0.7.0

**Megakernel fusion (`src/gpfuse.nu`, M8).** The GPU replay's wall on
small graphs is per-kernel launch latency — ~40 tiny dependent kernels
per episode, even under a CUDA graph. This generates anomaly's fused
aegpu shape FROM the captured tape instead of hand-writing it:

- **Row-space fusion** — a maximal consecutive run of row-local nodes
  (elementwise add/sub/mul/div, every unary, matmul `act[B,k]·W[k,c]`
  with a leaf `W`) becomes ONE generated kernel: block per row, threads
  stride each node's columns, `__syncthreads` between nodes. Backward
  splits into a row kernel (dActivations, hi→lo) and a param kernel
  (matmul dW and broadcast ew operands, serial over rows in
  `gp_bw_mm_b`/`gp_bw_accred` order).
- **Serial-space fusion** — the scalar tail (L2 sums, the final
  reduction, the loss ew chain) fuses into one single-block kernel.
- The whole episode — fused forward + backward + optimizer — runs under
  ONE CUDA graph (`gpfuse_graph_capture_train`). The N gradient zero
  fills collapse into one pointer-table kernel.

Every fused element uses the same intrinsic and inner-loop order as its
per-node kernel, so results are **bit-identical to the per-node replay**
and hold the same CPU-tape contract; `tests/gpfuse_test.nu` gates values
and gradients on both backends (bit-equal on cpu, 1e-12 on cuda). Nodes
outside the row/serial classes (attention bmm, softmax, slice/concat)
keep their per-node kernel automatically — a graph that fuses nothing
runs exactly as before.

Turnkey `gpfuse_open`/`gpfuse_episode`/`gpfuse_close` drive the same
three-call loop as the graph path with automatic fallback;
`gpfuse_worthwhile` gates production use to CUDA (the cpu backend has no
launch latency to remove). RTX 4090, d-64-32-64-d AE, batch 200, 360
episodes, all endpoints bit-equal to the CPU tape:

    cpu tape          1388 ms
    device replay      303 ms   4.6x
    per-node graph     236 ms   5.9x
    megakernel+graph    78 ms  17.8x

Fusion pays where a dense chain dominates (MLP/AE episodes). A graph whose
every segment is split by attention (bmm/softmax/slice) produces many tiny
fused kernels whose NVRTC compile cost can exceed the launch savings, so
such workloads are best left on the per-node path — the capability is an
explicit `gpfuse_open` call, not automatic, precisely so the caller
chooses per graph.

## 0.6.1

**f32 replay is now fast enough for a real model.** Two capture-time
costs that made f32 mode unusable on a 30-layer transformer are gone:

- `_gp_src` regenerated the entire f32 kernel source — ten full-source
  string passes over ~15 KB — on EVERY kernel launch (though only the
  kernel NAME feeds gpukit's cache), so a training run spent thousands of
  regenerations there. The source is constant; it is now built once and
  memoized. This was the whole slowdown: a nurllama LoRA finetune that
  stalled before step 10 now runs full speed (CE 5.86 -> 8.4e-5 in 40
  steps on SmolLM-135M).
- `_gp_upload_tensor`'s f32 path converted f64 -> f32 element-by-element
  on the host; it now uploads with a straight memcpy into a transient
  device buffer and converts with a kernel (`gp_f2f`), bounding both the
  host cost and the peak VRAM spike for large frozen weights.

No API or numerics change; gput_f32_test / gput_parity unchanged (5/5,
15/15).

## 0.6.0

**Float32 device replay.** `gput_capture_dt(kit, tp, loss, 1)` captures a
tape whose DEVICE replay runs in float32 — value, gradient, scratch and
optimizer-moment buffers are GK_F32, the kernels are the f32 variants
(derived from the f64 source by swapping the element type, the
round-to-nearest intrinsics and the libm transcendentals, and by
prefixing kernel names gp_ -> gpf_ so the two never collide in gpukit's
name-keyed cache). Device memory HALVES and the f32 ALUs run.

The CPU tape stays the f64 reference: an f32 program is NOT bit-equal
(that is the point). `tests/gput_f32_test.nu` trains a full AE both ways
and gates the gap at float32 tolerance — measured worst loss-trajectory
1e-5 relative and worst final-parameter 4e-4 relative over 30 Adam steps,
on CUDA and the CPU backend. The default (`gput_capture`) is unchanged
and stays bit-exact to the tape.

The host interface is untouched: `gput_set_input` / `gput_loss` /
`gput_grad` take and return f64, and gk_dbuf up/download convert. This is
the enabler for large-model finetune where f64 base weights would not fit
(a 0.5B model's ~4 GB of f64 consts becomes ~2 GB).

## 0.5.0

**Graph-fused episodes.** `gput_graph_capture(pg)` records one forward +
backward as a CUDA graph; `gput_graph_capture_train(pg, opt)` records the
WHOLE training episode including the optimizer update; `gput_episode(pg)`
replays it as ONE launch. The optimizer's per-step scalars (Adam lr_t,
the clip scale) moved into a small device ctl buffer — `gpopt_prepare` is
one 16-byte upload per step, and the clip scale is now computed ON the
device (`gp_clipcs`), so nothing inside the episode needs the host.
Bit-exactness is untouched: same kernels, same order, same values —
the bench gates the graph path's loss endpoints bitwise.

Honestly measured on the d-64-32-64-d AE bench (RTX 4090): per-node
replay 297 ms → graph-fused 236 ms (6.2× the CPU tape). The remaining
wall on tiny nets is GPU-side per-kernel latency (~40 small dependent
kernels), not host overhead — true kernel fusion is a future arc; the
graph win compounds with bigger nets where kernels do real work.

Requires gpu ^0.10 (CUDA Graphs). CPU-backend callers keep the
per-launch path automatically.

## 0.4.0

**`src/emitc.nu` — emit a recorded scalar tape as CUDA-C.**
`gemit_cuda_grad` walks a tape whose nodes are all single-element tensors
and prints the `__device__ void grad(long long x, double v, double* g,
const double* p)` function swarm-mcp's `compute_iterate` runs on every
worker: forward locals mirroring each op's exact arithmetic, a reverse
sweep under requires-grad propagation, and a `swarm_g_add` scatter per
parameter. Parameters bind to `p[j]` in list order; data leaves bind to
caller-supplied C expressions; frozen consts inline as round-trip float
literals. Distributed backward passes are now DERIVED from the tape, not
hand-written CUDA-C — the keystone plan's last missing verb.

- The C forms mirror grad.nu expression by expression, so a host build
  with `-ffp-contract=off` reproduces the tape bit for bit:
  `tests/emitc_oracle.sh` compiles the emitted function with gcc and
  asserts every parameter gradient is BIT-EQUAL to the tape's, on a loss
  touching every supported scalar op.
- Non-scalar nodes and linear-algebra ops are refused (emit returns F) —
  the per-example scalar loss is compute_iterate's shape.

## 0.3.0

**Requires-grad propagation (PyTorch's rule), on both engines.** A node
gets a gradient only if a PARAMETER lies in its ancestor cone. `backward`
computes a need set before the sweep and neither processes nodes outside
it nor accumulates into no-need inputs; the device engine additionally
allocates gradient BUFFERS only for backward-active nodes. Consequences:

- A frozen-const branch now costs nothing: no backward compute, no
  gradient memory. For LoRA over a large frozen model this is the
  difference between duplicating every base weight's size in gradient
  buffers (plus a full dW matmul per step for weights nobody updates)
  and paying only for the adapters. Parameter gradients and optimizer
  trajectories are bit-identical to 0.2.0 — const-side gradients never
  influenced them (leaves propagate nothing).
- Observable change: `grad_of` on an intermediate node with no parameter
  upstream now reports zeros (previously the true local gradient). The
  device engine's `gput_grad` mirrors that exactly.
- The const-zeroing backward epilogue is gone — nothing writes into
  no-need slots in the first place.

**The M6a LoRA transformer-block proof** (tests only): a Qwen2-style block
— RMSNorm, GQA attention with q/k/v bias + NEOX rotary embeddings + causal
mask, SwiGLU, lm_head, softmax cross-entropy — with LoRA pairs on
q/k/v/o/gate/up/down as the only parameters, expressed ENTIRELY in
existing ops (row reductions via ones-matmul, rotate-half via slice+concat,
GQA via per-head slices, CE pick via one-hot). Proven by finite differences
through the whole block (2e-7), the PEFT B=0 identity to the bit, a PyTorch
float64 oracle fed bit patterns (loss 3e-16, grads 1e-13), device replay
(bitwise on the CPU backend, 4e-14 on CUDA), and a 60-step on-device Adam
run (CE 2.65 → 0.92).

## 0.2.0

**The GPU replay engine (`src/gput.nu`) — device training, bit-exact.**
`gput_capture` mirrors one recorded episode (every node's value/gradient
buffer + kernel metadata) onto the device; per minibatch the caller uploads
fresh rows into their const slots, replays forward and backward with one
kernel launch per node, and steps the device optimizer (`gpopt_*`, opt.nu
mirrored: per-param L2, global-norm clip, host-pow Adam lr_t, the step
counter behind the heap pointer). Only the loss scalar returns per episode.

- **Bit-exactness, the aegpu discipline generalized per op**: explicit
  `__d*_rn` intrinsics (no fmad fusion), serial inner products and
  reductions in the CPU's documented index order, broadcast-reduce
  accumulation walking each slot's contributions in the CPU's row-major
  subsequence order. The exact tier — relu, +,−,×,÷, sqrt, matmul/bmm,
  sum/mean, transpose/reshape/slice/concat, SGD/Adam — is bit-equal to the
  CPU tape on BOTH backends; the transcendental tier (sigmoid/tanh/exp/
  log/softmax) mirrors the CPU formulas and is bit-equal on the gpu CPU
  backend, ~1 ulp on real CUDA.
- `tests/gput_parity_test.nu`: every node's forward value AND backward
  gradient bitwise vs the CPU tape (exact tier, both backends); trans tier
  pinned bitwise (cpu) / 1e-12 (cuda, measured ~2e-16); a 40-episode
  Adam+L2+clip training loop with a bit-equal loss trace and bit-equal
  final parameters.
- `tests/gput_bench.nu`: the d-64-32-64-d autoencoder, batch 200, 360
  episodes — ~5x over the CPU tape on an RTX 4090, loss endpoints
  bit-equal. (Per-node launches cannot fuse like anomaly/aegpu's
  four-kernel pipeline; the tape backend's win grows with the net.)
- Found and fixed upstream (gpu 0.9.1, gpukit 0.4.2, this package's new
  minimum): NVRTC fmad contraction made gpukit's f64 matmul/bmm kernels
  differ from the sequential host loop they claim to mirror — through
  tensor_matmul's silent >=100k-flop fast path, "CPU" tape results
  depended on whether a GPU was present. The kernels now spell their
  accumulation with rn intrinsics, and the gpu CPU backend gained the
  intrinsics + `-ffp-contract=off` so the discipline holds there too.
- Restrictions: TE_F64 tapes; g_bmm on the device requires both operands
  to carry the full batch. `gput_capture` fails closed with a message.

## 0.1.0

Reverse-mode automatic differentiation over `tensor`: define-by-run
tape-recording ops, one reverse sweep, exact gradients for every registered
parameter.

- **The tape**: a flat single-owner arena (`{op, a, b, scalar}` nodes + two
  parallel tensor arrays). No graph objects, no per-node closures; reverse
  index order is topological order, and the sweep order is deterministic.
  `grad_param`/`grad_const` copy in, `gvar_value`/`grad_of` lend borrows out,
  `tape_free` releases everything; `tape_mark`/`tape_reset_to` give the
  minibatch pattern (params survive, intermediates drop, arena capacity kept).
- **M1 op set (CPU)**: add/sub/mul/div (equal shapes), neg/adds/muls,
  relu/sigmoid/tanh/exp/log/sqrt (forwards mirror tensor's `__umap` formulas
  bit-for-bit), sum/mean (all axes), mse composite. Constants report zero
  gradient. A shape mismatch poisons the tape — `tape_ok` goes false and
  `backward` refuses — instead of half-computing.
- **Verification**: every rule double-checked — central finite differences
  over composite graphs (fan-out included) and analytic identities exact to
  the bit (`d/dx Σx² == 2x` bitwise; a post-reset episode bitwise equal to
  the pre-reset one).

M2 (same release): the linear-algebra spine.

- Binary ops broadcast with full numpy rules (forward through the tensor
  package); backward sums each input's contribution over its broadcast axes
  (`_g_acc_reduce`, one documented row-major accumulation order).
- `g_matmul` / `g_bmm` (dA = g·Bᵀ, dB = Aᵀ·g, serial inner sums),
  `g_transpose`, `g_reshape`, `g_softmax(axis)` (dx = y⊙(g − Σ g⊙y)),
  `g_slice` (backward scatters into the source window), `g_concat` (backward
  splits at the axis).
- Verification: 9 new finite-difference cases (23 checks total) and a
  **PyTorch float64 oracle** — one graph through every op, rebuilt in torch
  from the exact same input bits: loss agrees to ~1e-16 relative, every
  parameter gradient to ~1e-13.

M3 (same release): optimizers + the training-loop proof.

- `src/opt.nu`: SGD and Adam over tape parameters, per-parameter L2
  (`opt_add` — the param-groups need in miniature), optional global-norm
  clipping. Adam's step count lives behind the `*Opt` heap pointer (the
  frozen-t bug class cannot recur) and shares the ecosystem's Adam
  arithmetic (runtime `1−β` forms, matching mlp and the aegpu kernels).
- A parameter whose gradient backward() never touched is skipped, not
  decayed (PyTorch's None-grad rule).
- Verification: the two-step Adam trajectory, the SGD+weight-decay update
  and the clipped step are each asserted BIT-EXACT against hand-computed
  references; end to end, the d-64-32-64-d autoencoder trained with the
  mark/reset minibatch loop reaches 5.7e-5 MSE from 0.319 on a noisy 2-D
  manifold in 6-D (60 epochs, 360 episodes, arena healthy throughout).

Next: M4 mlp 0.3.0 refactored onto grad; M5 GPU backward.
