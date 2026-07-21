# grad — reverse-mode autograd over tensor

Build a computation with tape-recording ops that mirror
[`tensor`](../tensor)'s surface, call `backward(loss)` once, read exact
gradients for every parameter. Backward passes are **derived, not
hand-written** — the training keystone the registry was missing: `tensor`
gives the ops, `grad` gives the derivatives, everything above (MLPs, LoRA,
distributed training) becomes composition.

```
: *GTape tp ( tape_new )
: GVar w ( grad_param tp w0 )          // copied in; the tape owns the live copy
: GVar x ( grad_const tp batch )       // no gradient flows into a const
: GVar loss ( g_mse tp ( g_relu tp ( g_mul tp x w ) ) target )
( backward tp loss )
: Tensor gw ( grad_of tp w )           // borrowed view of dL/dw
...
( tape_free tp )                       // one owner, one free
```

## The tape model

Define-by-run: every `g_*` op computes its value eagerly and appends one node
to a flat tape (`{op, a, b, scalar}` + two parallel tensor arrays). Node
inputs always have smaller indices, so `backward` is a single reverse walk —
no graph objects, no per-node closures (deliberately: NURL closure capture is
the wrong tool for a hot loop), and reverse order is deterministic, which the
bit-exactness tests rely on.

**Ownership is single-owner by construction.** The tape owns every value and
gradient tensor. `grad_param`/`grad_const` copy in; `gvar_value`/`grad_of`
hand out borrows (never free them; invalid after `tape_free`/a reset past the
node); `tape_free` releases everything.

**The minibatch pattern** — parameters survive, episodes don't:

```
: i mark ( tape_mark tp )      // after registering params
~ training {
    ... build episode, backward, step optimizer ...
    ( tape_reset_to tp mark )  // drops intermediates, zeroes grads,
}                              // keeps arena capacity — no re-malloc
```

## Status

M1+M2 (this release, CPU):

- elementwise `g_add/sub/mul/div` with full **numpy broadcasting** (backward
  sums over the broadcast axes), `g_neg/adds/muls`,
  `g_relu/sigmoid/tanh/exp/log/sqrt` (forwards bit-identical to tensor's
  `__umap` formulas), `g_sum/mean/mse`;
- the linear-algebra spine: `g_matmul` / `g_bmm` (dA = g·Bᵀ, dB = Aᵀ·g),
  `g_transpose`, `g_reshape`, `g_softmax(axis)`, `g_slice`, `g_concat`;
- `backward`, the arena lifecycle.

M3 optimizers (`src/opt.nu`): **SGD** and **Adam** over the tape's
parameters, per-parameter L2 (`opt_add o tp p alpha` — weights carry alpha,
biases 0), optional **global-norm gradient clipping** (`opt_set_clip`). The
Adam step count lives behind the `*Opt` heap pointer so it advances — and the
trajectory is pinned bit-for-bit against a hand-computed reference in the
tests, the regression guard for the frozen-Adam-t bug class. Forwards for
matmul/bmm/broadcast/softmax/slice/concat go THROUGH the tensor package, so
grad inherits its semantics — and its GPU matmul path — verbatim.

## The GPU replay engine (M5, `src/gput.nu`)

The CPU tape stays the semantic reference; the device runs a bit-exact
REPLAY of it. Capture one recorded episode, then per minibatch upload fresh
input rows, replay forward + backward (one kernel launch per node), and step
the device optimizer — only the loss scalar comes back:

```nurl
: *GProg pg ( gput_capture kit tp loss )    // after ONE CPU-built episode
: *GpOpt go ( gpopt_adam_new lr )
( gpopt_add go pg W1 alpha ) …               // opt.nu mirrored, on-device m/v
~ training {
    ( gput_set_input pg X batch_rows )       // fresh minibatch
    ( gput_forward pg ) ( gput_backward pg )
    ( gpopt_step go pg )                     // lr_t from host pow, like opt.nu
}
( gput_param_sync_host pg tp )               // trained weights → the tape
```

**Bit-exactness, two documented tiers** (the anomaly/aegpu discipline
generalized per op): every kernel reproduces the CPU implementation's
rounding and order — explicit `__d*_rn` intrinsics so NVRTC cannot
fmad-fuse, serial inner products/reductions in the CPU's index order,
broadcast-reduce in the CPU's row-major subsequence order per slot. The
**exact tier** — relu, +,−,×,÷, sqrt, matmul/bmm, sum/mean, transpose/
reshape/slice/concat, SGD/Adam — is **bit-identical to the CPU tape on both
backends** (CUDA and the gpu package's CPU backend): a whole autoencoder
trains to a bit-equal loss trace and bit-equal final weights. The
**transcendental tier** (sigmoid/tanh/exp/log/softmax) mirrors the CPU
formulas exactly but calls the device's exp()/log(): bit-identical on the
CPU backend, ~1 ulp on real CUDA hardware.

Speed, honestly: the d-64-32-64-d / batch-200 autoencoder benchmark
(`tests/gput_bench.nu`) runs ~5× faster than the CPU tape on an RTX 4090.
Per-node launches cannot fuse the way anomaly's hand-written aegpu pipeline
does (4 launches per minibatch vs ~40 here), so on tiny nets aegpu keeps its
34× crown; the replay engine's win grows with layer width and batch — and it
works for EVERY graph the tape can record, not one hard-coded architecture.
On the gpu CPU backend the replay is far SLOWER than the CPU tape (per-launch
fiber-grid orchestration dwarfs the arithmetic): that backend exists so the
bit-exactness contract can be verified anywhere, not for training speed.

Device restrictions (capture fails closed, with a message): TE_F64 tapes;
`g_bmm` needs both operands to carry the full batch.

A shape mismatch **poisons the tape** (`tape_ok` → `F`, `backward` refuses)
rather than half-computing.

Gradients follow **requires-grad propagation** (PyTorch's rule): they are
computed and stored only where a parameter lies upstream. Frozen-const
branches — a LoRA base model, input batches — cost no backward compute and
no gradient memory on either engine; `grad_of` on such nodes reports zeros.

## Verification

Every backward rule is checked several independent ways:

- **central finite differences** over composite graphs (every op covered,
  fan-out included — worst observed relative error ~1e-8 at f64),
- **analytic identities**, exact to the bit where the arithmetic is exact:
  `d/dx Σx² == 2x` bitwise, forward sums bitwise equal to plain loops, an
  episode after `tape_reset_to` bitwise equal to the one before it, and
- a **PyTorch oracle** (`tests/oracle.sh`, skips without torch): one graph
  through every op — relu/softmax MLP + mse, tanh∘transpose∘reshape∘slice∘
  concat chain, sigmoid∘bmm — rebuilt in float64 torch from the exact same
  input bits; loss agrees to ~1e-16 relative, every parameter gradient to
  ~1e-13, and
- an **end-to-end training proof** (`tests/train_test.nu`): the classic
  d-64-32-64-d autoencoder trained with the tape + Adam on a noisy 2-D
  manifold in 6-D — 60 epochs of the mark/reset minibatch loop drive the MSE
  from 0.319 to 5.7e-5, past the noise floor, with the Adam/SGD/clip updates
  themselves asserted bit-exact against hand computations, and
- the **LoRA transformer-block proof** (`tests/lora_block_test.nu` +
  `tests/lora_oracle.sh`): a Qwen2-style block — RMSNorm, GQA attention with
  NEOX rotary embeddings and causal masking, SwiGLU, softmax cross-entropy —
  with LoRA adapter pairs on q/k/v/o/gate/up/down as the only parameters,
  expressed ENTIRELY in existing ops (row reductions via ones-matmul,
  rotate-half via slice+concat, CE pick via one-hot). Central differences
  through the whole block on all 14 adapters (worst ~2e-7), the PEFT B=0
  init identity bitwise (dL/dA ≡ 0, dL/dB ≠ 0), a PyTorch float64 oracle
  fed bit patterns (loss ~3e-16, grads ~1e-13), device replay of the block
  (~4e-14 on CUDA, bitwise on the CPU backend), and a 60-step on-device
  Adam run driving the CE loss from 2.65 to 0.92, and
- the **device parity suite** (`tests/gput_parity_test.nu`, skips without a
  backend): every exact-tier node's forward value AND backward gradient
  bitwise-equal to the CPU tape on both backends; the transcendental tier
  bitwise on the CPU backend and within 1e-12 relative on CUDA (measured
  ~2e-16); and a 40-episode Adam+L2+clip training run whose loss trace and
  final parameters are bit-equal to the CPU path.

## License

MIT OR Apache-2.0.
