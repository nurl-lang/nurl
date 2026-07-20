# Changelog

## 0.1.1

- Widen the gpu requirement to ^0.9: the CUBIN kernel cache removes the
  driver JIT at start-up, and large model uploads ride the pinned-staged
  parallel-stripe path. No API change.

## 0.1.0

Initial release — the pure-NURL embedding server.

- **XLM-RoBERTa-family encoder** (BGE-M3, multilingual-e5, …) loaded
  straight from a Hugging Face model dir (config.json + tokenizer.json +
  f32 model.safetensors); word/position/type embeddings + LayerNorm,
  N bidirectional attention blocks with exact-erf GELU FFNs, CLS or mean
  pooling, L2 normalize. Every device op is a gpukit `gkd_*` kernel — no
  kernel sources in this package; CUDA or the CPU/OpenMP backend.
- **Tokenization** via the tokenizer package's Unigram engine
  (token-identical to Hugging Face `tokenizers`).
- **`embed serve`** — the reference FastAPI embedding service's API,
  drop-in: POST/GET `/create_embedding` (`text` string or list,
  `normalize`), `/health`; Bearer-token auth with a constant-time
  compare; 401/400/500 always as JSON. Hardened: single worker, 16 MB
  body cap, 64 KB head cap, 30 s idle cut, 10 min deadline,
  panic-to-500. **`embed text`** for one-shot CLI embedding.
- **Verified**: cosine 1.0000000 per row vs sentence-transformers on a
  multilingual corpus; cosine 1.00000000 vs the reference service
  container over HTTP; CPU↔CUDA cosine 1.0; ASan/LSan clean.
