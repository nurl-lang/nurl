# Changelog — nurllama

All notable changes to the `nurllama` package.

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
