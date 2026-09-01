# Changelog

## 0.3.1

Dependency requirements now pin the **major**, matching the rest of the
registry packages:

- `tokenizer` `^0.3.2` → `^0`
- `safetensor` `^0.3` → `^0`
- `gpukit` `^0.7.0` → `^0`
- `gpu` `^0.11.2` → `^0`
- `hub` `^0.1` → `^0`

A minor release of a dependency is picked up on the next install now,
instead of stranding this package on the minor its requirement happened
to name.

No source change.

## 0.3.0

A batch of texts ran one forward per text, and the response was built a
JSON node at a time. Neither was visible in a single-text benchmark, and
together they were most of a batch request.

- **The forward is batched.** Texts are sorted longest-first, packed
  greedily into length-homogeneous chunks under a device-row budget, and
  each chunk is ONE forward — every kernel sees all of its sequences at
  once, on gpukit's new `gkd_attention_batch`, which reads Q/K/V in the
  `[batch·n, heads·hd]` layout the linear layers already produce. That
  also removes the eight `gkd_perm` round trips per block the
  single-text path paid to reach head-major order and back. The batch
  count is quantised the same way the sequence length already was, so
  buffer sizes stay a small set; the filler is whole dummy sequences,
  fully masked and pooled by a zero weight row.

  A chunk stays length-homogeneous on purpose: a text whose own bucket
  is under half the chunk's would spend more than half its rows on
  padding — at 16 real tokens in a 192-row slot that is 12× the
  arithmetic — and sorted longest-first it opens a cheaper chunk of its
  own instead.

  Measured on a 4090 against BGE-M3, one request of N texts, median of a
  dense warm run (texts/s):

  | one request of | 0.2.0 | 0.3.0 |
  |---|---|---|
  | 1 short text | 36 | 37 |
  | 16 short texts | 28 | ~500 |
  | 16 × 120 words | 27 | ~150 |
  | 32 mixed | 20 | 235 |

  0.2.0's throughput is flat at ~30 texts/s no matter how many texts the
  request carries, which is what "one forward per text" looks like from
  outside; 0.3.0's rises with the batch, which is the point.

- **The response body is built as one string, not a `Json` tree.** A
  64-text batch is ~65 000 floats; as `json_float` nodes that is 65 000
  allocations, and every one of their frees walked the panic-unwind
  journal the handler's panic→500 guard keeps — O(allocations²).
  Measured: **3.8 s of a 3.9 s request**. The numbers go through the
  same `nurl_str_float` formatter `json_stringify` uses, so the body is
  byte-identical to the tree's. (The journal's own quadratic behaviour
  is fixed in the runtime as well — see the language CHANGELOG — but a
  request handler had no business allocating 65 000 nodes to serialise
  an array of numbers.)

- **One queue job per REQUEST, not per text.** The model thread now
  receives a request's whole batch — flat ids plus offsets — so the
  texts reach the device together instead of being handed over one at a
  time behind the same lock.

- **`--gpu N` picks the CUDA device.** The default is unchanged (the
  best device, or `$NURL_GPU_DEVICE`), and it is usually right; when it
  is not, this says so explicitly. The ordinal is CUDA's — fastest
  first — which is NOT `nvidia-smi`'s PCI order, and the flag says so
  in `--help` because the mismatch is exactly the mistake it invites. A
  named ordinal must BE a CUDA device: falling back to the CPU backend
  behind an explicit `--gpu` would hide the mistake the flag exists to
  make loud. `embed_open_dev` is the library entry.

- **Long texts are ~1.7× faster**, from gpukit's re-tiled attention and
  wider gemm plus the tokenizer's de-quadraticised Viterbi: a 2000-word
  text **217 → 126 ms**. Nothing here changed the arithmetic the model
  does — only how it is blocked and how the text reaches it.

  | | 0.2.0 | 0.3.0 |
  |---|---|---|
  | one short text | 28 ms | 27 ms |
  | one ~120-word text | 30 ms | 21 ms |
  | one ~2000-word text | 197 ms | 126 ms |
  | 16 short, one request | 565 ms | ~30 ms |
  | 16 × 120 words, one request | 604 ms | ~105 ms |
  | 32 mixed, one request | 1576 ms | ~136 ms |
  | 16 concurrent clients | 70 req/s | 72 req/s |

  Concurrency is unchanged, and that is expected: fiber-per-connection
  with the forward on its own thread was already 0.2.0's, and sixteen
  clients each sending ONE text give the batching nothing to work with.
  What changed is the request that carries the texts together.

  A caveat on reading any of these: the card idles at 210 MHz and ramps
  to ~2.8 GHz under load, so a benchmark that does not warm it first
  measures the clock, not the code — a shape can read 1.7× slow on a
  cold card. Every number here is the median of a dense run after at
  least ten warm-up requests of the same shape.

- **The numbers are the same numbers.** 26 texts of wildly mixed length
  embed byte-for-byte identically whether sent as one batch or one at a
  time, and identically to 0.2.0 wherever the attention blocking did not
  change (short texts: exact; a 2000-word text: cosine 1.000000000, max
  element difference 1.8e-07, which is the f32 rounding any change of
  blocking moves). The committed golden — taken before the padded
  forward existed — still passes at cosine 1.00000000, and the shape
  test still reports a pool and kernel cache that stop growing
  (586 → 586 blocks, 10 → 10 kernels).

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
