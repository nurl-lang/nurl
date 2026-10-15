# Changelog — nurllama

All notable changes to the `nurllama` package.

## [0.21.2] — 2026-10-15

- Weight uploads are safe code. GGUF tensors are uploaded from `gguf_tensor_bytes` views with `gpu_upload_bytes`, dequantised ones with `gpu_upload_vec`, and the router bias with a new `__lm_scratch_from`. Only the q8_0 repack kernel launch stays `unsafe`, in its own helper. `unsafe` functions: 6 → 4.
- The MoE router bias was read through a raw pointer for `n_expert` × 4 bytes whatever the tensor's size. It is now read with the bounds-checked `bytes_read_u32_le`, and a short tensor fails the load instead of reading past it.
- Generation on the tiny q8_0 and f32 test models is identical to 0.21.1.

## [0.21.1] — 2026-10-14

### Changed

- The engine and finetune records start as literals of their empty values
  (`gpu_none`, `gpu_kernel_none`, `tok_empty`, `gguf_empty`, empty Vecs)
  instead of `locked_zero`: two `unsafe` functions fewer. What stays
  `unsafe` uploads device memory or launches kernels. Requires tokenizer
  0.4.6 and gguf 0.6.1.

## [0.21.0] — 2026-10-14

### Changed

- Finetuning follows grad 0.13: `ft_graph` takes the tape `inout`, and the device program it uploads into is passed `inout` too.

## [0.20.0] — 2026-10-14

### Changed

- 8 `unsafe` functions left (68 in 0.19.2): the kernel compile, the
  device uploads, the evaluation core that launches kernels over device
  addresses, and building an engine from zeroed memory.
- A `Llm` is its engine in a `Locked` beside its immutable record
  (tokenizer, vocabulary size, context, mask id, diffusion flag) in an
  `Arc`: an evaluation takes the engine for the call and gives it back,
  where it was an `Arc` changed through `arc_ptr` from any thread holding
  a copy — two requests evaluating at once raced on the KV cache and the
  scratch buffers. `llm_tok`, `llm_n_vocab`, `llm_n_ctx`, `llm_mask_id`
  and `llm_is_diffusion` never wait for an evaluation.
- `FtModel` is its training state in a `Locked`, likewise; the public
  calls take it and hand an `inout` view to their bodies, so a call that
  calls another (`ft_train_ck` → `ft_graph` → `ft_embed`) does not take
  it twice.
- The server's resident model is a `Locked` global set at start.
- Sampling reads a row of logits with one take of the engine
  (`llm_logits` / `llm_logits_row`, new) instead of one per logit;
  `exp` is the standard library's.
- `nurllama run`/`dgen` write generated text with `fd_write_all`; the
  pull's staging file starts as `file_none`; checkpoint F64 tensors are
  read through a checked byte view.
- Outputs are byte-identical to 0.19.2: logits, greedy and sampled
  generation (llama and llada2, f32 and Q8_0), and a LoRA finetune's
  adapters, checkpoint, resume, streamed run and merged model.

### Fixed

- tests/start_test.sh matched the wizard's `→` with `.`, which is one
  byte under a C locale: the checkpoint-listing check failed outside a
  UTF-8 locale.

## [0.19.2] — 2026-10-14

### Fixed

- A Gemma checkpoint's norm weights (stored as w − 1) were widened by
  `__lm_add1` through safetensor's `_st_u32`, which takes a byte view
  since safetensor 0.6 — it was still handed the buffer's raw address, and
  read it as a view of garbage length. The compiler accepted the
  ill-typed call; it rejects it now (h268). `__lm_add1` works on a view
  of the buffer and is no longer `unsafe`.

### Changed

- Requires gpukit 0.11 (its kit state behind a lock; census accessors return a `String`).

## [0.19.1] — 2026-10-14

Requires NURL 0.73.0 (`slice_at`, `slice_put`, `rc_take`, `locked_take`).

### Changed

- Loops that read or wrote through `vec_data` pointers index slices (`slice_at` / `slice_put`, as fast as the pointers), and functions with nothing raw in them are no longer marked `unsafe`.
- 2 fewer functions are `unsafe` than in 0.19.0 (67 left).
- Requires gguf 0.6 (`gguf_tensor_ptr` is `raw` there; the loaders that take tensor addresses were already `unsafe`) — its dequantiser is 2–4× faster.
- Requires gpu 0.17. The `lk_*` launchers take device addresses as plain integers and launch kernels that index them by the sizes they are given; they were safe to call with any numbers — now they are `raw` (their callers already vouched), and `lk_build`, which compiles this package's own kernel sources, is `unsafe`.
- Requires safetensor 0.6 (`st_tensor_ptr` is `raw` there; the loaders that take tensor addresses were already `unsafe`).

## [0.19.0] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held, a mutable module global may own a `String`, a `Vec`
or a handle, and a foreign function may take an `inout` parameter.
The published 0.18.3 does not compile under it.

### Changed

- The zero `File` handle the puller keeps until one is opened is built
  with the cast `# File # s 0`: a standard-library handle now holds its
  state in a `( Shared T )`.
- The resident model is a module global that owns it (an option: none
  is loaded until the first request), where it was an `Arc` kept as a
  word; the `--weights` path is an owned string, where it borrowed the
  command line's.
- The finetune loop's replaced buffers are dropped by the store; the
  `mem_take` before each is gone.
- Requires gpu 0.16 and grad 0.12.

### Removed

- `llm_into_word` and `llm_word_release`: a module global holds an
  `Llm` as it is.

## [0.18.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.18.2 does not compile under it.

### Changed

- `FtModel` and `Llm` keep their state in an `Arc` (stdlib/std/arc.nu)
  instead of an `rcbox`. The share and drop hooks are ordinary safe
  functions — the Arc does the counting — and so are the constructors that
  build one from a whole value; every copy is still the same state, and
  its last owner releases it.
- Its `--version` (or the version it reports) is read from `nurl.toml`
  with `( pkg_version )` instead of being written by hand, so it can no
  longer drift from the manifest.
- Requires gguf 0.5, safetensor 0.5, gpu 0.15 and gpukit 0.10.
- The safetensors second source is a `?St`; the GGUF is bound straight
  from `gguf_open`. A model kept in a server global is one owner behind a
  word made with `arc_into_word`.

### Fixed

- The package compiles again under NURL 0.72.0 and later.

## [0.18.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.18.1 does not compile under 0.72.0. The functions that do
are declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.18.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.18.0 does
not compile under 0.71.0.

## [0.18.0] — 2026-10-03

Nothing is released by hand any more. Requires NURL 0.69.0.

- `llm_open` / `llm_open_st` return an **`Llm` handle** (was `*Llm`) and
  `ft_open` an **`FtModel` handle** (was `*FtModel`): every copy is the
  same model, and its last owner releases the weights, the KV cache, the
  mappings and the device context. `llm_close` / `ft_free` are optional
  early releases; the `NURLLAMA_PROF` totals print when the model goes.
  A server keeps its resident model as one word (`llm_into_word` /
  `llm_word_release`).
- `cfg_free`, `chat_msg_free`, `chat_msgs_free`, `ft_train_free` and
  `lk_free` are gone: `NlConfig`, `ChatMsg`, `FtTrain` and `LlmKernels`
  are plain values the compiler drops.
- Follows the dependencies' handles: `tok_new` takes a `Gguf` and returns a
  `Tok` (was `*Gguf` → `*Tok`), `llm_tok` returns `Tok` (was `*Tok`),
  `chat_style_of` takes `Gguf`, and every `llm_*` / `ft_*` / `dz_generate`
  / `sample_*` function takes the `Llm` / `FtModel` handle instead of a
  pointer (`ft_graph` takes a `GTape` and `ft_stream_upload` a `GProg`
  handle from grad 0.11, both were pointers).
- `ft_graph` fills a `( Vec i )` of LoRA parameter ids (was a raw
  `*u` block the caller sized), and `ft_adapters_load` returns the rank
  through an `inout i` (was a `*u` cell). New shape accessors
  `ft_n_embd` / `ft_n_layer` / `ft_n_head` / `ft_n_kv` / `ft_head_dim` /
  `ft_n_vocab` / `ft_rope_style` and `ft_has_qk_norm`.
- The trainer's optional norm / bias tensors are values (`FtV`) rather
  than heap boxes behind raw words, and a NORM-rope q/k bias is now
  un-permuted in place: the old code built a literal from the boxed
  vector, which copies it, and un-permuted the copy. No llama-family
  model carries q/k biases, so no trained or merged output changes.

### Fixed

- Training again with an `FtModel` after `ft_merge_st` no longer trains on
  zero inputs: the merge consumes the host embedding table, and the next
  `ft_train` / `ft_train_ck` now streams it back from the GGUF along with
  the dropped base (`ft_reload_base` restores both). Before, every token
  embedded as a zero row, the CE sat at ln(n_vocab) and nothing learned.

## 0.17.7

The merged LoRA weight is no longer freed after its owner took it over (a double free under NURL 0.67.0, #1143).

## 0.17.6

`--version` reported 0.17.4 while the manifest said 0.17.5.

The string is a literal in the source and nothing derives it from `nurl.toml`,
so the bump to 0.17.5 moved one and not the other. A published version cannot be
replaced, only superseded — which is what this is.

## 0.17.5

`cfg_free`, `chat_msg_free`, `chat_msgs_free`, `ft_free`, `ft_train_free`, `lk_free` now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.17.4 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.

## 0.17.4

**Do not use 0.17.3.** It shipped the pin change below with a stale
`--version` literal — the binary announced `0.17.2`, a version whose
contents it does not have. A published version can be yanked but never
replaced, so the correction is this release: identical content, and
`--version` prints `0.17.4`.

## 0.17.3

Dependency requirements now pin the **major**, matching the rest of the
registry packages:

- `gguf` `^0.3` → `^0`
- `safetensor` `^0.3` → `^0`
- `tokenizer` `^0.3.0` → `^0`
- `gpu` `^0.11` → `^0`
- `grad` `^0.10` → `^0`
- `nn` `^0.1` → `^0`
- `gpukit` `^0.6` → `^0`
- `tensor` `^0.4` → `^0`
- `hub` `^0.1` → `^0`

A minor release of a dependency is picked up on the next install now,
instead of stranding this package on the minor its requirement happened
to name. That was not hypothetical here: a registry install
resolved `gpukit` to a 0.6 series while the monorepo builds this package
against 0.7 — two different builds of the same commit.

No source change.

## 0.17.2

- Requires `http ^0` instead of `^0.3`. http has been 0.4.0 since #1014
  and 0.4.0 is what this package is built and tested against in the
  repo, but the manifest still asked for `^0.3` — so an install from the
  registry resolved http 0.3.2 and compiled against different code than
  anything here was tested on. `nurlpkg publish` refuses on exactly that
  mismatch, which is how it surfaced. The caret sits on the major so a
  0.x minor release of http cannot silently re-open the same gap in
  every consumer.
- `--version` reports the manifest version.

## 0.17.1 — 2026-08-11

- Republish of 0.17.0: the 0.17.0 upload to the registry was corrupted
  by a transport failure and has been yanked; 0.17.1 is the same code.

## 0.17.0 — 2026-08-11 (yanked)

Serve/UX overhaul: the web chat server is usable straight from `serve`,
and every "that's not a model" path says what to do instead.

- **`serve [model]`** (also `--model MODEL`): the server now takes a
  default model — the web UI chats with it, and an `/api/generate` /
  `/api/chat` request that names no model of its own falls back to it.
  Previously the bare `serve` hosted a web UI that answered **500 to
  every message**, because only `nurllama start` could configure a model.
  The model is resolved at startup, so a bad name fails immediately with
  guidance instead of as a 500 on the first chat.
- **Real error messages in the web UI.** `/web/chat` failures now carry
  the actual reason ("no model is configured — restart the server with
  a model: nurllama serve MODEL…", or the load error), the UI displays
  the server's message instead of `[error: http 500]`, and a server with
  no model shows a banner on page load saying chat will not work yet.
- **`serve --weights` without a model is refused** with an explanation:
  `--weights` replaces the tensors of a model, it does not select one —
  `nurllama serve base.gguf --weights merged.safetensors`.
- **run/chat/serve no longer download a whole repository.** A bare
  `org/repo` ref used to fetch every safetensors shard (gigabytes) and
  then fail, because run/chat need a GGUF. It is now refused up front
  with the three working forms: `org/repo/model.gguf`, `nurllama convert
  org/repo model.gguf`, or `--weights merged.safetensors` over a GGUF.
  An argument with no slash (a typo, or a name missing from the store)
  lists what a model argument can be instead of surfacing a raw
  `hub: cannot list the repository (HTTP 401)`.
- The served model is echoed under the name you gave (`qwen3-4b`), not
  its resolved blob path.
- `/api/show`'s "not found" error now says how to list and pull models.

## 0.16.0

- `serve --weights FILE` — the API twin of `run --weights`: every model
  the server opens takes its tensors from the given safetensors file
  (the GGUF still supplies hyperparameters and the tokenizer), so a
  finetuned/merged checkpoint serves over the ollama-compatible API.

## 0.15.0

- `finetune --window-stride N` — step k trains window `(k·N) mod nwin`;
  `0` picks a golden-ratio stride coprime with `nwin`, so even a short
  run samples the whole corpus evenly while an epoch still visits every
  window exactly once. Recorded in the checkpoint; resuming under a
  different stride is refused.
- `finetune --merge-only` — skip training, read the adapters file
  (`--out`) back and write the merged model (`--merged`); the
  low-memory recovery path after a crash between adapter save and merge.
- The streamed merge lost three memory peaks (four OOM kills on a 31 GB
  box merging a 4B model): layer bases page out after their last use,
  the embedding copy is consumed once written, and safetensor 0.3.2
  streams exact-capacity chunks to disk.

## 0.14.0

- `finetune --checkpoint FILE [--save-every N] [--resume]` — resumable
  training: LoRA values, both Adam moments and step counters written
  atomically (tmp + rename) every N steps and after the last one. A
  killed-and-resumed run replays the uninterrupted one bit for bit.

## 0.13.0

- The **qwen3** architecture: NEOX rotary, no Q/K/V bias, stated
  `head_dim`, per-head Q/K RMSNorm — every one silent when wrong, so
  verified against an independent numpy implementation (identical
  argmax/top-5, text-identical greedy continuation). Training carries
  the same shape; `--merged` writes the q_norm/k_norm weights.
- `finetune --stream` — base weights stream onto the device one tensor
  at a time: Qwen3-0.6B trains in 6.1 GB of host RAM instead of 13.8,
  with a step-0 loss identical to the last bit.
- Fixed: the unsupported-architecture error printed freed bytes.

## 0.12.1

- Correctness fix for the `--weights` path: genuine HF llama-family
  checkpoints store rotary q/k lanes half-split, but the NORM rope
  kernel rotates adjacent lanes — every real HF llama/SmolLM/TinyLlama
  checkpoint ran with misrotated attention and produced fluent-looking
  garbage. The loader now applies the converter's interleave at load;
  `finetune --merged` writes true HF lane order (regenerate merged
  files written by 0.12.0).

## 0.12.0

- `nurllama finetune <model.gguf> <data.txt>` — LoRA training on the
  GPU over the `grad` autograd tape; adapters save as safetensors,
  `--merged` writes a full runnable model. Proven by a wiring oracle
  against the inference engine (top-1 identical) and by the merged
  model reproducing its training sentence.
- Fixed: an HF tensor-name collision silently enabled a spurious
  per-layer normalization for every real HF llama/qwen2 checkpoint.

## 0.11.1

- `NURLLAMA_PROF=1` also prints a load-phase breakdown; model uploads
  ride gpu 0.9.0's pinned-staged parallel-stripe path.

## 0.11.0

- Diffusion decode 3× faster (llada2.1-mini q8_0: 33.7 s → 11.5 s)
  without changing a single generated token: fully on-device MoE FFN,
  GPU-reduced greedy decode, q8_0 repacked for aligned reads, a
  batch-reuse output projection, and freeze re-eval skipping.
  `NURLLAMA_PROF=1` prints a per-phase GPU time breakdown.

## 0.10.0

- `nurllama start` — an interactive setup wizard (model, bind scope,
  open/bearer-token access, port → `$NURLLAMA_HOME/config.json`) that
  launches the server; `start -y` reuses the config unprompted.
- The server hosts a self-contained **web chat UI** at `/`: per-browser
  cookie GUIDs, conversations persisted to SQLite scoped to the client,
  token-auth gating of every `/web/*` and `/api/*` endpoint when
  configured.

## 0.9.0

- **Diffusion language models**: the llada2 architecture (LLaDA2.x MoE)
  and its block-denoise decode with LLaDA2.1 editing — proven to
  produce ids identical to a reference-faithful python loop.
- `nurllama convert` — HF checkpoint directory → llama.cpp-convention
  GGUF, streaming at constant memory, verified tensor-for-tensor.

## 0.8.0

- The tokenizer engine moved into its own package (`tokenizer`) —
  loadable from GGUF metadata or HF `tokenizer.json`; parity tests
  against independent python SentencePiece/BPE still pass token for
  token.

## 0.7.0

- `run --weights model.safetensors` — weights from the container HF
  actually ships, with the GGUF supplying hyperparameters and
  tokenizer. Reproduces HF transformers' logits to max|Δ| = 1.1e-4.

## 0.1.0 – 0.6.x

The engine arc: GGUF parsing and the quantised formats (Q4_0…Q6_K),
llama/qwen2/gemma3/phi3 architectures read from each model's own
metadata, SentencePiece + byte-level BPE tokenizers, the
content-addressed model store with resumable sha256-verified pulls,
`run`/`chat`/`serve` with the ollama-compatible API, warp-per-row CUDA
matvecs with the CPU/OpenMP backend producing byte-identical output,
and batched prompt prefill.
