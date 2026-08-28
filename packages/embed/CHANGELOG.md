# Changelog

## 0.2.0

A server that looked like it was reloading the model at random, and that
served one client at a time. Both were real, and neither was where it
looked.

- **The forward pads to a quantised sequence length.** Every buffer and
  every shape-specialised kernel in the forward is a function of the
  token count, and both are cached BY SHAPE: gpukit pools device blocks
  by exact byte size, and `gkd_perm` bakes its dims into the kernel name.
  One text per length meant a new set of both, every request. Measured
  against BGE-M3 on a 4090: a request at a length never seen before took
  **385 ms against 36 ms warm**, three NVRTC compiles of it, and the
  device-buffer pool grew **4 GB → 10.8 GB over two hundred requests**
  and kept going — until the driver refused, at which point the whole
  pool was dumped and re-allocated. That dump is what "it offloads and
  reloads the model" looks like from outside.

  Sequence lengths are now quantised to four steps per octave (at most
  25% padding past 32 tokens, ~40 distinct lengths over the model's whole
  8192-token range) and the padding is masked out of attention and of
  pooling. The same two hundred varied-length requests: **8.2 s instead
  of 68.5 s**, and device memory flat at +236 MB instead of +6.7 GB. A
  500-request random-length soak reaches a steady state after ~200
  requests and does not move again.

  The padding is invisible in the numbers, not merely small: the
  committed golden — taken with the unpadded, composed-attention
  implementation and verified against sentence-transformers at cosine
  1.0000000 — still reproduces at **cosine 1.00000000 per row**.

- **Attention is the fused kernel** (`gkd_attention_masked`, gpukit
  0.6.5) with the padding mask, instead of bmm + scale + softmax + bmm.
  The composed form materialised three `[heads, n, n]` buffers, which at
  8192 tokens is 4.3 GB each; nothing of that size is allocated now.
  Resident scratch after startup dropped from 4.0 GB to 2.5 GB and the
  warm forward from 36 ms to 30 ms. The composed path remains, with the
  same mask, for the CPU backend and for head widths the fused kernel is
  not sized for.

- **Serving is fiber-per-connection with one model thread.** One model
  on one device runs one forward at a time and that is not a choice, but
  reading the socket, parsing JSON, tokenizing (the Unigram engine is
  read-only, so it is re-entrant) and serialising a few thousand floats
  are, and for a batch they are the larger half. A single worker meant a
  slow or idle client stalled every other client behind it. Throughput
  on 2000-word texts: **3.1 req/s against 2.1**, and flat from 1 to 32
  concurrent clients where it used to be strictly serial. Sixteen
  concurrent requests return byte-identical vectors to the same sixteen
  run one at a time (now a test).

  The forward runs on a thread rather than on the requesting fiber for a
  hard reason: async fibers get 64 KB stacks and NVRTC wants far more,
  so compiling a kernel on a fiber segfaults inside libnvrtc.

- **The device is `gk_open_best`, not ordinal 0.** On a box with an old
  card in front of a new one — a 4 GB GTX 970 ahead of a 24 GB RTX 4090
  — ordinal 0 is where 2.3 GB of weights plus activations do not fit.
  `$NURL_GPU_DEVICE` still overrides.

- **`{"texts": [...]}` is accepted**, alongside `{"text": ...}`. The
  package has described both since 0.1.0; only one of them worked.

- **`normalize: false` no longer reconfigures the engine.** It used to
  flip the engine's pooling config around the call and flip it back —
  which a panic could leave flipped, and which no concurrent server could
  be allowed to do at all. It is a parameter now.

- `/health` also reports `device_name`, `max_seq`, `pool_blocks` and
  `pool_idle_bytes`, so "where did the VRAM go" is a question the server
  answers.

- New test `tests/embed_shapes.nu`: many distinct lengths must stop
  growing the pool and stop compiling kernels — the regression test for
  the bug above. `tests/embed_test.sh` also stands a real server up and
  checks auth, both body spellings, a batch, `normalize`, and serial vs
  16-way-concurrent agreement.

- Requires gpukit `^0.6.5`, gpu `^0.11.2` and http `^0`. The http
  requirement had drifted: the local copy this package is built and
  tested against has been 0.4.0 since it was published, while the
  manifest still said `^0.3` — so everyone installing from the registry
  resolved 0.3.2 and compiled against different code than the tests ran
  on. `nurlpkg publish` refuses on exactly that, which is how it
  surfaced. The caret sits on the major so a 0.x minor release of http
  cannot silently re-open the same gap.

## 0.1.5

- Requirements widened to gpu `^0.11` / gpukit `^0.6`. No source change.

## 0.1.4

- The model argument to `embed serve` / `embed text` can now be a Hugging Face
  ref (e.g. `embed serve BAAI/bge-m3`), not only a local directory. A ref is
  fetched into the shared `~/.nurl/models` cache via the new `hub` dependency
  (resumable, sha256-verified) and the downloaded directory is used; an existing
  local path is passed straight through unchanged. New dependency: `hub ^0.1`.

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
