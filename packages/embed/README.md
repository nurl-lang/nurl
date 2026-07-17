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
| `GET /create_embedding?text=…&normalize=true` | single text, query-encoded |
| `GET /health` | `{"status":"healthy", "model", "model_loaded", "device": "cuda"\|"cpu", "dimension", "requests"}` |
| `GET /` | same as /health |

**Auth.** Without `--token` the server is open — bind loopback only (the
default `127.0.0.1:8000`). With a token, requests need
`Authorization: Bearer <t>` (or `?token=<t>` where headers are not an
option); the comparison is constant-time over the configured token.
Wrong/missing token → 401, malformed JSON → 400, an embedding failure →
500 — always JSON, never a stack trace.

**Hardening.** One worker (one model on one device — concurrency would
serialise on it anyway), 16 MB body cap, 64 KB header cap, 30 s slowloris
idle cut, 10 min request deadline, handler panics become 500s.

## CLI

```
embed serve <model-dir> [--addr HOST:PORT] [--token T] [--maxseq N]
                        [--pool cls|mean] [--no-normalize]
embed text  <model-dir> <text>          # one-shot: vector as CSV on stdout
```

`--maxseq` caps tokens per text (default: the model's full context, 8192
for BGE-M3 — memory scales with n² in attention; 8192 tokens peak around
4.3 GB of activations). Long inputs truncate head-first with `</s>`
re-appended, sentence-transformers style.

## How it runs

Everything device-side is gpukit's dtype-generic dev-layer kernel
library (`gkd_*`) — the same kernels the tensor and onnx packages run
on; this package contains **no kernel sources**. Launches chain on the
stream with one sync per forward. CUDA when a device is present, the
gpu package's CPU/OpenMP backend otherwise (identical results, cosine
1.0 between backends). A short text embeds in ~40 ms on an RTX 4090 —
after a one-time model load (~2.3 GB of weights) at startup.

Batching: a batch request loops single-text forwards. That keeps every
row's numerics exactly equal to the single-text case (no padding, no
attention mask) — and the forward pass dominates at embedding sizes
anyway.

## Tests

`tests/embed_test.sh` — re-embeds the committed multilingual corpus and
requires cosine ≥ 0.99999 per row against the committed golden (which
was verified at cosine 1.0000000 against sentence-transformers and the
reference FastAPI container); then an ASan pass. Skips cleanly without
a local model. `--oracle` re-checks against sentence-transformers,
`--regen` rewrites the golden.
