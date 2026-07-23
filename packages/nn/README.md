# nn — neural-network layers on the grad tape

The reusable middle the training stack was missing. `grad` derives
gradients over a tape of primitive tensor ops; `nn` is the layer library on
top of it — the pieces you actually assemble a model from, each a pure tape
builder so backward is derived, device replay (`gput`) and megakernel fusion
(`gpfuse`) come free, and there is exactly one place the math lives.

```
: GVar xn   ( nn_rmsnorm tp x n1 ones h eps )
: GVar q    ( nn_lora_linear tp xn wq aq bq scale )
: GVar kk   ( nn_lora_linear tp xn wk ak bk scale )
: GVar vv   ( nn_lora_linear tp xn wv av bv scale )
: GVar ctx  ( nn_gqa_attention tp q kk vv cos sin mask t nh nkv hd iscale )
: GVar loss ( nn_cross_entropy_rows tp logits onehot onesV keep )
```

## Layers

Every layer takes a `* GTape` and input `GVar`s and returns a `GVar`. Weights
are the caller's — register them with `grad_param` / `grad_const` (or the
`nn_param` / `nn_const` helpers) and call `backward(loss)` once.

- **Linear** — `nn_linear` (x·W), `nn_linear_bias`, `nn_lora_linear`
  (x·W0 + scale·(x·A)·B).
- **Normalization** — `nn_rmsnorm`, `nn_layernorm`.
- **Activations** — `nn_silu` (x·σ(x)), `nn_swiglu` (SiLU(gate)⊙up),
  `nn_softmax`.
- **Positional** — `nn_rope` (NEOX half-split rotary), `nn_rope_fill` (the
  cos/sin tables), `nn_causal_mask_fill`.
- **Attention** — `nn_head` (head slice), `nn_gqa_attention` (grouped-query:
  per-head rope, scaled scores, masked softmax, weighted sum, concat).
- **Loss** — `nn_cross_entropy`, `nn_cross_entropy_rows` (next-token: keep
  the first N rows, since the last position has no target).
- **Helpers** — `nn_const`, `nn_param`, `nn_ones`.

## Provenance and verification

The math is lifted from two places that had proven it and were drifting
apart: grad's PyTorch-float64 LoRA-block oracle
(`grad/tests/lora_block.nu` + `lora_oracle.sh`, loss and every adapter
gradient to 1e-11) and nurllama's finetune path. This package is the single
home; nurllama's finetune now consumes it (its private `__ft_*` copies are
gone), verified byte-for-byte on SmolLM-135M.

- `tests/nn_oracle.sh` — the Qwen2-style block rebuilt from `nn` primitives,
  gated against the same PyTorch f64 reference: **loss rel 3.3e-16, worst
  adapter gradient 1.0e-13** over 14 adapters.
- `tests/nn_test.nu` — shape gates for every layer plus **central
  finite-difference** checks through the two new layers (LayerNorm, SwiGLU)
  and SiLU (worst rel ~1e-9 vs a numeric ±h probe).
- `tests/nn_block_test.nu` — torch-free gate (block builds, loss sane,
  backward runs, every adapter gradient finite and non-zero).

## Dependencies

`grad` (^0.7), `tensor` (^0.4). An `nn` graph is an ordinary `grad` graph,
so anything grad's replay/fusion does, it does for `nn` models too.

## License

MIT OR Apache-2.0
