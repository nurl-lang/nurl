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

M1 (this release): CPU elementwise + all-axes reductions —
`g_add/sub/mul/div` (equal shapes), `g_neg/adds/muls`,
`g_relu/sigmoid/tanh/exp/log/sqrt` (forwards bit-identical to tensor's
`__umap` formulas), `g_sum/mean/mse`, `backward`, the arena lifecycle.
Binary broadcasting, matmul/bmm, softmax/reshape/slice and optimizers land in
M2–M3; the GPU backward (gpukit, aegpu-style bit-exactness) in M5.

A shape mismatch **poisons the tape** (`tape_ok` → `F`, `backward` refuses)
rather than half-computing.

## Verification

Every backward rule is checked two independent ways in `tests/grad_test.nu`:

- **central finite differences** over composite graphs (every op covered,
  fan-out included — worst observed relative error ~1e-8 at f64), and
- **analytic identities**, exact to the bit where the arithmetic is exact:
  `d/dx Σx² == 2x` bitwise, forward sums bitwise equal to plain loops, an
  episode after `tape_reset_to` bitwise equal to the one before it.

## License

MIT OR Apache-2.0.
