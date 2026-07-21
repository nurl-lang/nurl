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
tests, the regression guard for the frozen-Adam-t bug class. The GPU backward
(gpukit, aegpu-style bit-exactness) lands in M5. Forwards for matmul/bmm/broadcast/softmax/slice/concat
go THROUGH the tensor package, so grad inherits its semantics — and its GPU
matmul path — verbatim.

A shape mismatch **poisons the tape** (`tape_ok` → `F`, `backward` refuses)
rather than half-computing.

## Verification

Every backward rule is checked two independent ways in `tests/grad_test.nu`:

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
  themselves asserted bit-exact against hand computations.

## License

MIT OR Apache-2.0.
