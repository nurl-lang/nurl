# Changelog

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
