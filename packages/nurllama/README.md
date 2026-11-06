# nurllama

Run language models locally. Pull a GGUF model, chat with it, or serve
an **ollama-compatible** and an **OpenAI-compatible API** your existing
clients already speak — all in pure NURL, from the GGUF parser to the
GPU kernels.

```sh
nurlpkg install nurllama
```

## Sixty seconds

```sh
$ nurllama pull hf.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/qwen2.5-0.5b-instruct-q4_k_m.gguf
qwen2.5-0.5b-instruct-q4_k_m [=============>    ] 74%  294.1 MB / 397.8 MB  31.2 MB/s
pulled qwen2.5-0.5b-instruct-q4_k_m (sha256:5c1e0d97a2b4…, 397.8 MB)

$ nurllama run qwen2.5-0.5b-instruct-q4_k_m "The capital of France is" -n 12
 Paris. It is the largest city in Europe and the third

$ nurllama chat qwen2.5-0.5b-instruct-q4_k_m
chat ready — /exit to quit
> what is a GGUF file?
It is a container format for model weights…

$ nurllama serve qwen2.5-0.5b-instruct-q4_k_m
nurllama serving on http://127.0.0.1:11434
```

That last line is three things at once: the **ollama-compatible API**,
the **OpenAI-compatible API** under `/v1`, and a **web chat UI** — open <http://127.0.0.1:11434> in a browser and talk
to the named model. The model you pass to `serve` is the default: the
web UI chats with it, and an API request that names no model of its own
falls back to it. (Without a default, the web UI cannot chat and an API
request must carry `"model"` — `serve` will tell you so rather than
answering 500.)

```sh
$ curl localhost:11434/api/generate -d '{"prompt":"Once upon a time"}'
{"model":"qwen2.5-0.5b-instruct-q4_k_m","response":",","done":false}
{"model":"qwen2.5-0.5b-instruct-q4_k_m","response":" there","done":false}
…
{"model":"qwen2.5-0.5b-instruct-q4_k_m","done":true,"prompt_eval_count":5,"eval_count":40}
```

One object per token, the moment it decodes. `stream:false` returns a
single aggregated object instead. Naming a different model in the
request (`"model":"SmolLM-135M.Q4_K_M"`) swaps it in — one model is
resident at a time.

## Commands

| | |
|---|---|
| `start [-y]` | interactive setup wizard → config + a **web chat server** (below). `-y` reuses the saved config. |
| `pull <src> [--name N]` | `hf.co/ORG/REPO/FILE.gguf` or any URL. Resumes an interrupted download. |
| `run <model> "<prompt>"` | `-n` tokens, `--temp` (0 = greedy), `--topk`, `--topp`, `--seed`, `--ctx` |
| `chat <model>` | interactive; uses the model's own chat template |
| `serve [model] [--host] [--port] [--weights F]` | ollama- and OpenAI-compatible APIs + web chat UI on 11434; `model` is the default the web UI and the APIs use |
| `list` · `rm <name>` · `verify <name>` | the local store |
| `convert <hf-dir> <out.gguf> [--type T]` | HF checkpoint → GGUF (`q8_0` default, `f16`, `bf16`, `f32`) |
| `tokenize` · `detok` · `vocab` · `logits` | inspection taps |

`<model>` is one of three things, tried in this order:

1. a **path** to a `.gguf` file — `./qwen3-4b.gguf`
2. a **name** from the local store — `nurllama list`
3. a **Hugging Face ref naming a `.gguf` file** —
   `Qwen/Qwen2.5-0.5B-Instruct-GGUF/qwen2.5-0.5b-instruct-q4_k_m.gguf`,
   fetched on demand into the shared `~/.nurl/models` cache

A bare `org/repo` is **not** a model argument for run/chat/serve: that
names a whole safetensors checkpoint repository, which these commands
could not open anyway, so nurllama refuses it *before* downloading
gigabytes and prints the working forms. To run an HF checkpoint that
ships no GGUF, convert it first:

```sh
$ nurllama convert org/repo model.gguf     # safetensors checkpoint → GGUF
$ nurllama serve model.gguf
```

**HTTP API:** `POST /api/generate`, `POST /api/chat`, `GET /api/tags`,
`POST /api/show` (ollama's), and `POST /v1/chat/completions`,
`POST /v1/completions`, `GET /v1/models`, `GET /v1/models/{id}`
(OpenAI's).

### The OpenAI-compatible API

Point any OpenAI client at `http://HOST:11434/v1`:

```python
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:11434/v1", api_key="unused")
r = client.chat.completions.create(model="qwen2.5-0.5b-instruct-q4_k_m",
        messages=[{"role": "user", "content": "Why is the sky blue?"}])
print(r.choices[0].message.content)
```

```sh
$ curl localhost:11434/v1/chat/completions -d '{"messages":[{"role":"user","content":"hi"}],"stream":true}'
data: {"id":"chatcmpl-…","object":"chat.completion.chunk",…,"choices":[{"index":0,"delta":{"role":"assistant","content":""},…}]}
data: {…"choices":[{"index":0,"delta":{"content":"Hello"},…}]}
…
data: {…"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
data: [DONE]
```

* `messages` go through the model's own chat template; `content` is a
  string or an array of `text` parts (`developer` is read as `system`).
* `max_tokens` / `max_completion_tokens`, `temperature`, `top_p`, `seed`,
  `stop` (a string or an array) and `stream` with
  `stream_options.include_usage` behave as OpenAI documents them, with
  OpenAI's defaults (temperature 1, top_p 1; a chat runs to the end of its
  turn, a completion to 16 tokens). `top_k` is taken too.
* Every response carries `usage`; `finish_reason` is `stop` (end of turn
  or a stop sequence) or `length` (the token budget or the context).
* A stop sequence is never sent, not even the part of it that arrived
  first: a stream holds back what might be the start of one until the
  next token says otherwise, and a token that ends inside a UTF-8
  character waits for the rest of it. Bytes a model emits that are not
  UTF-8 reach the client as U+FFFD — JSON is UTF-8 — the same streamed or
  not.
* What the server cannot do is refused with OpenAI's error shape rather
  than ignored: `n` > 1, `tools`, a `response_format` other than text,
  `logprobs`, image or audio content.
* `stop` (as `options.stop`) and `finish_reason` (as `done_reason`) work
  on ollama's routes too: both protocols run one generation loop.

A server started with a token (`nurllama start`) answers every data
route — `/api/*`, `/v1/*` and `/web/*` — only with
`Authorization: Bearer <token>`; an OpenAI client sends its `api_key`
exactly that way.

## Serving a finetuned model

`--weights FILE` runs a model with its tensors taken from a safetensors
file — the GGUF still supplies the hyperparameters and the tokenizer,
which safetensors does not carry. This is how a `finetune --merged`
checkpoint runs and serves:

```sh
$ nurllama finetune qwen3-4b.gguf data.txt --merged qwen3-4b-tuned.st
$ nurllama run   qwen3-4b.gguf "test prompt" --weights qwen3-4b-tuned.st
$ nurllama serve qwen3-4b.gguf --weights qwen3-4b-tuned.st
```

The GGUF and the safetensors must be the **same architecture and
shape** — the usual pair is the base model's GGUF plus your merged
finetune of it. `--weights` alone selects nothing (it replaces the
tensors *of* a model), so `serve --weights` without a model is refused
with exactly that explanation. Under `serve`, every model the server
opens uses these weights — serve one model when using it.

## What it runs

**Architectures:** `llama`, `qwen2`, `qwen3`, `qwen35`, `gemma3`, `phi3`, `llada2` and `glm-dsa`. Each model's own
metadata decides the details that actually change the output — get one
wrong and the model still runs while quietly producing nonsense, so
nurllama reads them from the file rather than guessing:

* **llama** — RMSNorm → GQA attention with rotary → SwiGLU, rotating
  adjacent pairs of each head (NORM).
* **qwen2** — adds Q/K/V biases and rotates the two halves of a head
  together (NEOX), with its own BPE pre-tokenizer variant.
* **qwen3** — NEOX like qwen2 but with the biases **gone**, `head_dim`
  stated outright (Qwen3-0.6B is 16 heads × 128 = 2048 against an
  `n_embd` of **1024**, so the attention projections do not land back on
  `n_embd`), and Q and K RMSNormed *per head* before the rotation. All
  four are silent when wrong — the model runs either way — so they are
  checked against an independent numpy implementation reading the same
  GGUF (`tests/qwen3_ref.py`): identical argmax and top-5, a max logit
  delta of 5.1e-5 against a span of 31.6, and a 20-token greedy
  continuation that is text-identical. Training carries the same shape:
  the LoRA tape applies the per-head norm, `--merged` writes the
  `q_norm`/`k_norm` weights, and the wiring oracle (tape top-1 ==
  engine top-1) closes the chain numpy → engine → tape.
* **gemma3** — a different shape throughout: the embedding row is scaled
  by `sqrt(n_embd)`, `head_dim` is stated outright rather than being
  `n_embd / n_head` (gemma3-270m: 640/4 = 160, but head_dim is **256**),
  Q and K are RMSNormed *per head* before the rotation, every block norms
  its own output before the residual add, the FFN gate is GeGLU, and five
  of every six layers attend only within a **512-token sliding window**
  — those layers using their own, smaller RoPE base.

* **phi3** — the llama shape, but Q/K/V arrive as **one** tensor
  (`attn_qkv`) and the FFN gate and up as one (`ffn_up`). Nothing is
  split apart: a weight here is a device pointer plus a row count, so the
  parts are row *ranges* inside the uploaded tensor — and every range
  lands on a block boundary, because a row is a whole number of
  quantisation blocks.

* **qwen35** — Qwen3.5 and Qwen3.8 (`model_type qwen3_5`), a **hybrid**.
  Three layers of every four are **Gated DeltaNet** — linear attention
  whose memory is a recurrent state, not a KV cache: a causal
  convolution over the last four inputs, q and k L2-normalised, and per
  value head a dk×dv state that decays by `exp(A·softplus(α + dt))` and
  takes the delta rule `S += k ⊗ β(v − Sᵀk)`; its output is RMSNormed per
  head and gated by `silu(z)`. The fourth layer is full attention whose
  query projection also carries an **output gate** (`out · σ(gate)`),
  with per-head Q/K norms and NEOX rotary on only the first quarter of a
  256-wide head. The states hold every position seen so far, so a
  sequence starts at position 0 or continues where it stopped; only the
  full-attention layers keep a KV cache (a quarter of the layers). The
  file's multi-token-prediction block is not run. The tokenizer is
  qwen2's split with combining marks in the word class (`qwen35`), and a
  chat template that thinks only when asked gets the empty
  `<think></think>` its own generation prompt adds by default. Dense
  models only for now (Qwen3.5-0.8B…27B, Qwen3.8-27B); the MoE
  variants (35B-A3B and up) are not supported yet.

* **llada2** — LLaDA2.x, a **diffusion** MoE, and a different *decode*,
  not just a different shape. Attention is bidirectional; generation
  fills a template of mask tokens one block window at a time, committing
  every position whose confidence clears a threshold in parallel and
  *revising* already-committed tokens the model changes its mind about
  (the LLaDA2.1 editing step). Layers 1+ route each position through 8
  of 256 small experts — an fp32 sigmoid router with a selection-only
  bias and group-limited top-k — plus one always-on shared expert; the
  256 experts live fused in one 3D tensor per projection and are
  evaluated as row ranges, still quantised, the phi3 trick at scale.
  Completed blocks freeze their K/V into the cache, so a denoise step
  costs O(window) where the reference implementation recomputes the
  whole prefix. `nurllama convert` turns the HF checkpoint into the
  GGUF (llama.cpp's `llada2` conventions); `run`/`chat`/the API detect
  the diffusion decode from the model's own metadata
  (`--block`, `--threshold`, `--edit-threshold`, `--post-steps`).

* **glm-dsa** — GLM-5.x (`model_type glm_moe_dsa`), in llama.cpp's GGUF
  layout. Three things set it apart, every one of them silent when wrong:
  - **MLA attention.** The query comes through a low-rank `q_a` → norm →
    `q_b`; K and V both come out of ONE compressed latent per position
    (`kv_a` → norm), with a single shared rotary key beside it. nurllama
    runs it in the *absorbed* form: each head's query is taken into the
    latent space through that head's `k_b`, so every head attends the same
    cache row `[latent | rope]` (multi-query attention) and the head's
    output comes back through its `v_b`. The cache holds that one row —
    576 floats a position for GLM-5 — not per-head keys and values.
  - **DeepSeek sparse attention.** A lightning indexer (its own small
    query and LayerNormed key, ReLU scores weighted per indexer head)
    picks the `index_topk` keys each position attends; a "shared" layer
    attends the selection its last "full" layer made. Up to `index_topk`
    keys that is every key — the selection only starts to cut beyond it.
  - **MoE** — the sigmoid router with a selection-only bias of llada2,
    weights normalised and scaled, plus a shared expert, after
    `leading_dense_block_count` dense layers.

  Checked against HF transformers' own `GlmMoeDsaForCausalLM` on a tiny
  random checkpoint converted by llama.cpp (`tests/glm_dsa_test.sh`): same
  argmax and top-5 with a logit delta near 1e-5 of the span, and
  text-identical greedy continuations, for prompts inside and past the
  indexer's top-k and across a prefill chunk; the GLM tokenizer (`glm4` /
  `glm5`: digits in threes, whole-piece pre-tokens kept) gives HF's ids.

A chat template writes its turn markers (`<start_of_turn>`,
`<|im_start|>`, …) into the prompt as *text*; nurllama emits each as its
own token id, as llama.cpp does. Tokenised as ordinary text they shred
into a dozen pieces and the model answers a question you did not ask.

**Quantisations:** F32, F16, BF16, Q4_0, Q4_1, Q5_0, Q5_1, Q8_0 and the
K-quants **Q4_K / Q5_K / Q6_K** (the `Q4_K_M` files people actually
download).

Weights stay **quantised on the device**: the matvec kernels decode
GGUF blocks inside the matmul, so a Q4_K_M model needs about a third of
the memory its f32 expansion would — 189 MiB instead of 603 MiB for
SmolLM-135M — and the memory-bound matmul reads proportionally fewer
bytes. The embedding table is never expanded either: each step
dequantises just the token's row, straight out of the mmapped file.

The prompt is processed in **batched chunks** — the matmuls and the
attention run over 64 positions at once — so a long prompt does not
crawl: a 301-token prompt reaches its first generated token in 1.2 s
instead of 7.2 s.

On CUDA the matvecs give one **warp** per output row — the warp walks the
row's quantised blocks together and the 32 lanes split each block, so
every load is a contiguous span, and a shuffle reduction folds the lane
partials. Attention runs in two parallel passes instead of one thread per
head. Together: **249 tok/s for Qwen2.5-0.5B Q4_K_M on an RTX 4090**, up
from 62.

Every kernel is a [gpukit](../gpukit) **checked kernel**: it reaches its
buffers only through bounds-checked loads and stores, so nurllama holds no
pointer and has no `unsafe` code. The weights are byte buffers read with
16- and 32-bit word loads, and a block or a row is a window checked once,
so the checks inside a loop fold away. The outputs are bit-identical to
the raw CUDA-C kernels they replaced, and decode is faster: Qwen3-14B
Q4_K_M 56.7 → 50.7 ms a token, Qwen3-0.6B Q8_0 3.81 → 3.63 ms. A
forward pass is recorded once per call shape and replayed with the new
position.

**No GPU?** `NURL_GPU=cpu` runs the portable kernels on the host through
OpenMP and produces byte-identical output — the CUDA-only variants are a
dispatch choice, never a behaviour change.

## Configuration

| | |
|---|---|
| `NURLLAMA_HOME` | store location (default `~/.nurllama`) |
| `--ctx N` | context length (default 4096, or the model's own if smaller) |
| `NURL_GPU=cpu` | run on the CPU backend |
| `NURLLAMA_VERBOSE=1` | report device memory at load |
| `NURLLAMA_DEQUANT=host` | force the f32 reference path (debugging) |
| `NURL_GPU_CACHE=off` | disable the compiled-kernel cache |

The store is content-addressed — `blobs/sha256-<hex>` plus one manifest
per name — so two names can share a blob, and `verify` re-hashes it in
a stream and refuses drift.

## `nurllama start` — the web chat server, configured once

`serve <model>` already gives you the web chat UI on localhost. `start`
is the same server behind a saved config: it walks you through model,
bind scope, access and port once, then reuses the answers.

```sh
$ nurllama start
── nurllama setup ──
Models directory [/home/you/models]:
Models:
  1) llada2.1-mini-q8_0.gguf   (16.1 GB)
  2) qwen2.5-0.5b-instruct-q4_k_m.gguf   (397 MB)
Choose a model [1]: 1
Network:
  1) localhost only (127.0.0.1)
  2) reachable from the network (0.0.0.0)
Choose [1]: 2
Access:
  1) require a bearer token
  2) open (anyone who can reach the port)
Choose [1]: 1
Token [Enter = generate]:
Port [11434]:
Saved config → ~/.nurllama/config.json
nurllama serving on http://0.0.0.0:11434
```

The wizard's answers are written to `$NURLLAMA_HOME/config.json`. A second
`nurllama start` offers to reuse them; `nurllama start -y` reuses them
without asking. Everything the wizard asks — model, bind scope, access,
port — you can also just edit in the JSON.

The model list holds `.gguf` files **and** Hugging Face checkpoint
*directories* (a folder with `config.json` and `*.safetensors`). A bare
`.safetensors` file is not listed on its own — it carries only tensors,
no hyperparameters and no tokenizer, so it cannot be served — but a
checkpoint directory is offered with `(HF checkpoint → convert to GGUF)`,
and picking it runs `nurllama convert` (Q8_0) and serves the result. An
already-converted GGUF beside it is reused after a prompt.

The server it launches is the ollama- and OpenAI-compatible APIs **plus** a
self-contained web chat UI at `/` (no external requests — it embeds its
own CSS and JS). A programmatic client that hits `/` still gets the
`nurllama is running` status line; a browser gets the chat page. Each
browser is issued a GUID in an `nl_client` cookie, and **every
conversation — each turn, both sides — is persisted to
[nurldb](../nurldb)** (the database directory `$NURLLAMA_HOME/history`)
scoped to that GUID, so a client only ever sees its own history. A reply
of any length is kept whole. The server holds the database's lock while
it runs, so a second server on the same `NURLLAMA_HOME` stops at startup
with "the database is already open" instead of writing the same files. When the wizard chose token access, the page is
served to everyone but every `/web/*` and `/api/*` request must carry
`Authorization: Bearer <token>` (the UI prompts for it once and
remembers it).

| endpoint | |
|---|---|
| `GET /web/session` | mint/refresh the cookie; returns the client id + model |
| `GET /web/conversations` | this client's conversations, newest first |
| `GET /web/conversations/:id/messages` | one conversation (owner-checked) |
| `DELETE /web/conversations/:id` | delete one (owner-checked) |
| `POST /web/chat` | `{conversation_id, content}` → generates against the full history, persists both turns, returns `{conversation_id, reply}` |

## Chat templates

The template comes from the model's own metadata
(`tokenizer.chat_template` → ChatML, llama3, llama2, gemma, phi3,
bailing or GLM; a ChatML template that thinks only when `enable_thinking` is
true — Qwen3.5's — gets its default empty `<think></think>` block). A model with no
template is a **base** model, and nurllama will not invent turns for it
— it completes your text, which is what such a model was trained to do.

GLM has two: GLM-5.2 / 5.3's (`[gMASK]<sop><|system|>Reasoning Effort:
Max`, an empty `<think></think>` on every earlier assistant turn) and
GLM-5 / 5.1's (also GLM-4.7's: an earlier turn's reasoning dropped to a
bare `</think>`). Both are checked byte for byte against HF's
`apply_chat_template` on the models' own templates
(`tests/glm_dsa_test.sh`), and both open the reply with `<think>` — the
templates' default is to reason.

A generation ends on any of the model's end-of-generation ids — its eos,
and its end-of-turn and end-of-message ids where the GGUF states them
(`tokenizer.ggml.eot_token_id` / `eom_token_id`), as llama.cpp reads them.
GLM ends its turn with `<|user|>`, its eot, not with its eos.

## Finetuning (in progress — the M6 arc)

`src/finetune.nu` trains **LoRA adapters** on a model over the [`grad`](../grad)
autograd tape: `ft_open` lifts the GGUF weights into f64 host tensors and
`ft_graph` builds the whole transformer forward + next-token cross-entropy as
one tape graph — LoRA pairs on q/k/v/o and gate/up/down are the only
parameters, and grad's requires-grad propagation makes the frozen base free.
Training replays the captured episode on the GPU (`gput`). Proven on a real
SmolLM-135M: the tape's logits match the inference engine's (top-1 identical,
2e-7 on the top logit), and 40 device Adam steps overfit a sentence from CE
2.75 to 8.7e-6. llama-family NORM rope is handled by un-permuting q/k columns
at load (half-split rope then reproduces the exact rotations; scores are
permutation-invariant). `--f32` runs the device replay in float32 (half the base-weight VRAM;
float32 precision, not bit-exact to the f64 tape) for larger models. The
PEFT reference curve lands next in this arc.

**`--stream`** is what makes a model past ~1B trainable on an ordinary
machine. Eagerly, every base weight is lifted into f64 host tensors *and*
cloned into the tape's own const, so the host peak is two copies of the whole
model at the moment of capture — 13.8 GB for Qwen3-0.6B, 2.9× the model's own
f64 size. A frozen weight is read exactly once, when the capture uploads it,
so there is no reason for it to be resident at all: with `--stream`, `ft_open`
reads the *shapes*, `ft_graph` declares each base weight as one of grad's
lazy consts, and `ft_stream_upload` fills each device buffer straight from
the GGUF after the capture, freeing it before the next. Same run, 6.1 GB
instead of 13.8, and the step-0 loss is identical to the last bit — f64
replay and f32 alike (`tests/finetune_stream_test.nu`). The values go through
the same loader the eager path uses, NORM-rope un-permute included, so there
is one definition of what a base weight is, not two that must agree.

**`--checkpoint FILE [--save-every N] [--resume]`** makes a long run
survivable. Every N steps (default 200) — and once more after the last step —
the trainer writes one safetensors file holding the LoRA parameter values,
both Adam moment vectors and the step counters: everything the update rule
reads. The write goes to `FILE.tmp` and then `rename(2)`s over `FILE`, so a
crash mid-write leaves the previous checkpoint intact. `--resume` loads it
and continues the schedule exactly where it stopped (the window round-robin
is a function of the step index), refuses a checkpoint whose shape or rank
does not match the run, and starts fresh when the file does not exist — so
one command line is idempotent: run it, and rerun it until the merge lands.
The tensors are stored at the device's own precision (F64 for the f64
replay, F32 for `--f32`/`--mixed`), so a resume is a lossless round-trip:
a run killed at step 100 of 200 and resumed produces adapters
**byte-identical** to the uninterrupted run (`tests/finetune_ckpt_test.nu`,
and the same check killed-for-real over the CLI).

**`--window-stride N`** picks which window step k trains: `(k·N) mod nwin`.
The sequential default (1) means a run shorter than one epoch reads only
the corpus *head* — a 4000-step seq-56 run over a 7.4M-token corpus sees
3% of it, all from the front. `--window-stride 0` chooses a golden-ratio
stride made coprime with `nwin`, which turns the schedule into a
permutation of the windows: any prefix samples the whole corpus evenly and
a full epoch still visits every window exactly once. The schedule stays a
pure function of the step index, so checkpoint resume replays it exactly —
the stride is recorded in the checkpoint, and resuming under a different
one is refused rather than silently changing which data the run sees
(`tests/finetune_sched_test.nu`).

## How it is checked

Not by trusting itself:

- Token IDs match an independent Python SentencePiece implementation on
  a real model — unicode, emoji, whitespace runs, empty input included.
- Final-position logits match an independent **numpy** implementation of
  the whole forward pass, and a greedy continuation is text-identical to
  it — for llama *and* for qwen2, whose biases and NEOX rotary the
  reference implements independently.
- The quantised device kernels agree with the host dequant oracle —
  itself bit-identical to an independent decoder — and the CPU backend
  reproduces the same text exactly.
- A resumed download is proven to send `Range:` and transfer only the
  missing tail, with the final digest still exact.
- An 872-token prompt — fourteen chunk boundaries — continues exactly as
  the numpy reference does, so the batching cannot quietly corrupt a
  long context.
- The llada2 path has its own oracle chain: `convert` round-trips a
  python-crafted checkpoint tensor-for-tensor (expert fusion order,
  BF16 widening, Q8_0 error bounds); an f32 conversion's logits match
  an independent numpy forward — MoE router, groups, shared expert,
  partial rotary, bidirectional window — to max|Δ| = 1e-6; the
  bailingmoe2 tokenizer is token-for-token equal to HF `tokenizers` on
  a 16-case multilingual battery; and the block-denoise loop produces
  ids **identical** to a reference-faithful python loop that recomputes
  everything each step — proving the frozen-K/V cache changes nothing.
- The qwen35 path is checked the same way, on Qwen3.5-0.8B: an
  independent numpy forward (`tests/qwen35_ref.py`) — itself held
  against HF transformers' own Qwen3_5 model on the original checkpoint
  (`tests/qwen35_hf_check.py`) — gives the same argmax and top-5 with
  max|Δ| ≈ 2e-5 against a logit span of ~27, and greedy continuations
  are text-identical, for a short prompt and for a 110-token one whose
  DeltaNet states cross a prefill chunk boundary into decoding — on the
  CUDA backend and on the CPU backend. Token ids equal HF `tokenizers`
  on English, accented, Devanagari, polytonic Greek, half-width and
  Arabic-digit text. Qwen3.5-4B, whose value heads outnumber its key
  heads two to one, is checked too: the GGUF's tiled head order was
  matched tensor by tensor against the HF checkpoint, and its greedy text
  matches the reference.
- ASan/UBSan/LeakSanitizer-clean.

```sh
./tests/tokenizer_test.sh && ./tests/infer_test.sh   # NURL_NET_TESTS=1 adds real models
./tests/store_test.sh && ./tests/api_test.sh
./tests/convert_test.sh && ./tests/llada_infer_test.sh && ./tests/bailing_tok_test.sh
./tests/start_test.sh    # wizard, config, cookie sessions, history store and scoping, token auth
./tests/qwen35_test.sh   # QWEN35_GGUF=… (or NURL_NET_TESTS=1); QWEN35_TOKENIZER=tokenizer.json adds the split
```

## Built on

[`gguf`](../gguf) — the container and its dequantisation — and
[`gpukit`](../gpukit) over [`gpu`](../gpu) — CUDA/NVRTC, or the same
kernels on the CPU. The web chat's history is a [`nurldb`](../nurldb)
database.

## License

MIT OR Apache-2.0
