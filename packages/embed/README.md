# embed

The embedding server, in pure NURL. Load an XLM-RoBERTa-family text
encoder — BGE-M3, multilingual-e5, … — from a Hugging Face model
directory and serve embeddings over HTTP. No Python, no PyTorch, no ONNX
export step: tokenizer.json and model.safetensors are read directly.

```
nurlpkg install embed
embed serve ~/models/bge-m3 --addr 0.0.0.0:8000 --token s3cret
```

```
$ curl -s -H "Authorization: Bearer s3cret" -H "Content-Type: application/json" \
    -d '{"text": ["Hello, world!", "Hei maailma!"]}' \
    http://localhost:8000/create_embedding | jq '.dimension, (.embeddings|length)'
1024
2
```

Verified against sentence-transformers: **cosine 1.0000000 per row** on a
multilingual corpus (Latin, CJK, Cyrillic, Arabic, emoji, NFKC edge
forms), and drop-in API-compatible with the reference FastAPI embedding
service — the same request bodies, the same response shape, the same
auth.

## The model directory

The standard Hugging Face layout, three files of it:

| file | read by |
|---|---|
| `config.json` | layer/head/dim/eps shape |
| `tokenizer.json` | the tokenizer package's **Unigram** engine (Precompiled charsmap normalization + true Viterbi; token-identical to HF `tokenizers`) |
| `model.safetensors` | the safetensor package (mmap; tensors must be f32) |

Get BGE-M3's files from `huggingface.co/BAAI/bge-m3` (the safetensors
revision). Any `XLMRobertaModel` checkpoint with f32 safetensors works;
for models pooled by averaging (multilingual-e5) pass `--pool mean`.

## HTTP surface

| route | behaviour |
|---|---|
| `POST /create_embedding` | `{"text": "…" \| ["…", …], "normalize": true}` → `{"embeddings": [[…]], "model": "…", "dimension": N}` |
| | `{"texts": ["…", …]}` is accepted for the same thing |
| `GET /create_embedding?text=…&normalize=true` | single text, query-encoded |
| `GET /health` | `{"status":"healthy", "model", "model_loaded", "device": "cuda"\|"cpu", "dimension", "requests"}` |
| `GET /` | same as /health |

**Auth.** Without `--token` the server is open — bind loopback only (the
default `127.0.0.1:8000`). With a token, requests need
`Authorization: Bearer <t>` (or `?token=<t>` where headers are not an
option); the comparison is constant-time over the configured token.
Wrong/missing token → 401, malformed JSON → 400, an embedding failure →
500 — always JSON, never a stack trace.

**Concurrency.** Fiber-per-connection, with the forward handed to one
model thread over a queue. One model on one device runs one forward at a
time and that is not a choice — but reading the socket, parsing JSON,
tokenizing and serialising a few thousand floats back out are, and for a
batch they are the larger half of the work. On 2000-word texts that is
3.1 req/s against 2.1, flat from one to thirty-two concurrent clients.
Sixteen concurrent requests return byte-identical vectors to the same
sixteen run one at a time.

**Hardening.** 16 MB body cap, 64 KB header cap, 30 s slowloris idle
cut, 10 min request deadline, handler panics become 500s.

## CLI

```
embed serve <model-dir> [--addr HOST:PORT] [--token T] [--maxseq N]
                        [--pool cls|mean] [--no-normalize]
embed text  <model-dir> <text>          # one-shot: vector as CSV on stdout
```

`--maxseq` caps tokens per text (default: the model's full context, 8192
for BGE-M3). Long inputs truncate head-first with `</s>` re-appended,
sentence-transformers style. Attention is the fused kernel, so nothing of
size n² is ever allocated — 8192 tokens no longer means gigabytes of
score matrix.

## How it runs

Everything device-side is gpukit's dtype-generic dev-layer kernel
library (`gkd_*`) — the same kernels the tensor and onnx packages run
on; this package contains **no kernel sources**. Launches chain on the
stream with one sync per forward. CUDA when a device is present (the
*best* device, not driver ordinal 0 — `$NURL_GPU_DEVICE` overrides), the
gpu package's CPU/OpenMP backend otherwise (identical results, cosine
1.0 between backends). A short text embeds in ~20 ms on an RTX 4090 —
after a one-time model load (~2.3 GB of weights) at startup.

**The sequence length is quantised.** Every buffer and every
shape-specialised kernel in the forward is a function of the token count,
and both are cached by shape: gpukit pools device blocks by exact byte
size, and `gkd_perm` bakes its dims into the kernel name. One text per
length is therefore a new set of both, every request — which measured, on
BGE-M3 on a 4090, as **385 ms for a length never seen before against
36 ms warm** (three NVRTC compiles of it), with the device-buffer pool
growing 4 GB → 10.8 GB over two hundred such requests and no ceiling in
sight; the dump-and-re-allocate when the driver finally refuses is what
"it reloads the model" looks like from outside. So a sequence is padded
up to one of about forty lengths (four steps per octave: at most 25%
padding past 32 tokens) and the padding is masked out of attention and of
pooling. The same two hundred requests take 8.2 s instead of 68.5 s, and
device memory settles instead of climbing.

The mask is what makes that a change of shape and not of numbers: a
padded key never reaches attention's running maximum and contributes
exactly zero to its denominator, and pooling weighs it 0. The committed
golden — taken before any of this, and verified against
sentence-transformers at cosine 1.0000000 — still reproduces at cosine
1.00000000 per row.

Batching: a batch request loops single-text forwards. That keeps every
row's numerics exactly equal to the single-text case, and the forward
pass dominates at embedding sizes anyway.

## Tests

`tests/embed_test.sh` — four things:

1. re-embeds the committed multilingual corpus and requires cosine
   ≥ 0.99999 per row against the committed golden (verified at cosine
   1.0000000 against sentence-transformers and the reference FastAPI
   container). Since the golden predates the padded forward, this is
   also the padding-invariance proof.
2. `tests/embed_shapes.nu` — many distinct sequence lengths must stop
   growing the device-buffer pool and stop compiling kernels.
3. a live server: auth, both body spellings, a batch, `normalize`, and
   sixteen concurrent requests that must agree byte-for-byte with the
   same requests run serially.
4. an AddressSanitizer pass.

Skips cleanly without a local model. `--oracle` re-checks against
sentence-transformers, `--regen` rewrites the golden.
