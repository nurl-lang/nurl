# Changelog

## [0.2.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.2.0 does
not compile under 0.71.0.

## [0.2.0] — 2026-10-03

**Nothing is released by hand.** Every layer takes the tape as grad 0.11's
`GTape` handle instead of a `* GTape` pointer: `nn_const`, `nn_param`,
`nn_ones`, `nn_linear`, `nn_linear_bias`, `nn_lora_linear`, `nn_rmsnorm`,
`nn_layernorm`, `nn_silu`, `nn_swiglu`, `nn_softmax`, `nn_rope`, `nn_head`,
`nn_gqa_attention`, `nn_cross_entropy` and `nn_cross_entropy_rows`
(`* GTape tp` → `GTape tp`). Callers pass the `GTape` that `tape_new`
returns. Requires grad ^0.11 and tensor ^0.6.

The layers no longer free their scratch (the const tensors handed to
`grad_const` / `grad_param`, the ones vector, the slice start/size vectors):
the compiler drops them. Results are unchanged — the PyTorch oracle
(`tests/nn_oracle.sh`) still agrees to ~1e-13 on all 14 adapter gradients.
