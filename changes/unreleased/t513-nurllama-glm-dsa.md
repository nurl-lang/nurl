### Added

- **nurllama runs GLM-5.x (`glm-dsa`)** (Agora #513). MLA attention in
  the absorbed form (every head attends one shared `[latent | rope]` cache
  row; per-head `k_b` / `v_b`), DeepSeek sparse attention (the lightning
  indexer's top-k selection, "shared" layers reusing the last full
  layer's), and the sigmoid-routed MoE with a shared expert, read from
  llama.cpp's `glm-dsa` GGUF layout. The tokenizer reads the `glm4` /
  `glm5` pre-split (digits in threes) with `ignore_merges`.
  `tests/glm_dsa_test.sh` checks logits and greedy text against HF
  transformers on a tiny random checkpoint.
