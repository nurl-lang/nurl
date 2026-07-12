# nurllama — run language models locally, in pure NURL

The ollama-shaped engine, built package by package on top of
[`packages/gguf`](../gguf) and [`packages/gpu`](../gpu).
**Phase 6 (current): quantised weights run natively on the device.**

```
$ nurllama pull hf.co/ggml-org/models/tinyllamas/stories260K.gguf
pulled stories260K (sha256:270cba1bd510…, 1.1 MB)
$ nurllama serve                      # ollama-compatible, port 11434
$ curl localhost:11434/api/generate -d '{"model":"stories260K","prompt":"Once upon a time"}'
{"model":"stories260K","response":",","done":false}
{"model":"stories260K","response":" there","done":false}
…
$ nurllama chat mymodel               # interactive, model's own template
$ nurllama run stories260K "Once upon a time" -n 40 --temp 0
, there was a little girl named Lily. She loved to play outside in the
park. One day, she saw a big, red ball.

nurllama pull <hf.co/ORG/REPO/FILE.gguf | url> [--name N]
nurllama list · rm <name> · verify <name>
nurllama serve [--host H] [--port N] · chat <name|path>
nurllama run <name|path> "prompt" [-n N] [--temp F] [--topk N] [--topp F] [--seed N]
nurllama logits model.gguf "prompt"               # verification tap
nurllama tokenize model.gguf "Once upon a time"   # → 1 403 407 261 378
nurllama detok model.gguf 1 403 407 261 378       # → " Once upon a time"
nurllama vocab model.gguf 10                      # first 10 pieces
nurllama selftest                                 # 17 bit-exact checks
```

## The API and chat

`nurllama serve` speaks enough of ollama's wire protocol that existing
clients work unchanged: `POST /api/generate` and `POST /api/chat` emit
**NDJSON — one object per token, the moment it decodes** (`stream:false`
returns a single aggregated object instead), plus `GET /api/tags`,
`POST /api/show` and a health root. Streaming rides a new
`http_app_stream` hook in the http package: the handler owns the
TcpConn and writes chunked frames itself.

Chat templates come from **the model's own GGUF metadata**
(`tokenizer.chat_template` → ChatML / llama3 / llama2). A model with no
template is a *base* model, and nurllama refuses to invent turns for it
— it completes text, which is what such a model was trained to do.
`nurllama chat` runs the same renderer over a live message list with a
line editor and streaming output.

One model is resident at a time; a request for another swaps it in.
The server is single-worker, so decode serialisation is structural
rather than a lock — honest for a single-GPU host.

## Model store

`~/.nurllama` (or `$NURLLAMA_HOME`): content-addressed blobs
(`blobs/sha256-<hex>`) plus one small manifest per name. The pull is
streaming end to end — HTTP chunks flow straight to disk while the
incremental sha256 consumes the same bytes and a tty-gated progress
bar narrates; nothing is ever fully resident. An interrupted pull
resumes with `Range: bytes=N-` (the existing part is re-hashed in a
stream and only the tail transfers; a server without Range support
triggers a clean restart). `verify` re-hashes the blob and refuses
drift; `rm` drops the blob only when the last name referencing it is
gone. `run`/`show`/`tokenize` accept a store name or a plain path.

## Quantised inference

Weights stay in their **GGUF block form on the device** — the matvec
kernels decode Q4_0 / Q4_1 / Q5_0 / Q5_1 / Q8_0 / **Q4_K / Q5_K /
Q6_K** blocks inside the matmul. A Q4_K_M model therefore needs ~3×
less device memory than its f32 expansion (measured: 603 → 189 MiB for
SmolLM-135M) and the memory-bound matvec reads proportionally fewer
bytes. `NURLLAMA_DEQUANT=host` forces the f32 reference path — the two
must agree, and the test suite proves they do (identical top-5 logits,
identical greedy text). A type without a device kernel falls back to
host dequantisation automatically: correctness first, always.

## Inference core

The full llama-family forward pass — RMSNorm, GQA attention with
NORM-style RoPE, SwiGLU FFN, residuals, device-resident f32 KV cache —
as CUDA-C kernels compiled through `packages/gpu`: NVRTC on the CUDA
backend, and the *same source* on the CPU/OpenMP backend
(`NURL_GPU=cpu`), which produces byte-identical greedy output. Weights
load through `gguf_dequant`, so F32/F16/BF16/Q4_0/Q4_1/Q8_0 models all
run; sampling (greedy / temperature / top-k / top-p, seeded) is
host-side over the downloaded logits; generated pieces stream to
stdout as they decode.

v1 honesty: weights expand to f32 on load (device-side
dequant-in-matmul is the planned optimisation for models whose f32
expansion is too large), prefill runs the decode step per prompt
token, and one model runs at a time.

## Tokenizer from the model file alone

Everything is loaded from the model's own `tokenizer.ggml.*` GGUF
metadata — vocabulary, scores, token types, merges, special ids and
the add-BOS/EOS flags. No external vocab files, no exporter step.

Two families, selected by `tokenizer.ggml.model`:

- **SPM (`llama`)** — SentencePiece-style bigram merging: space-escape
  (` ` → `▁`, optional leading space), split to UTF-8 characters, then
  repeatedly merge the adjacent pair whose concatenation is the
  highest-scoring vocab piece — llama.cpp's `llm_tokenizer_spm`
  selection order exactly (ties break leftmost). Unmatched characters
  fall back to the `<0xNN>` byte tokens, then to UNK.
- **BPE (`gpt2`)** — byte-level BPE: GPT-2's byte→unicode remap,
  contraction/letter/digit/punct/whitespace pre-split, then
  lowest-merge-rank pairing from `tokenizer.ggml.merges`.
  *v1 note:* the pre-split approximates `\p{L}` as "ASCII letters +
  any codepoint ≥ 0x80"; per-model `tokenizer.ggml.pre` variants
  (qwen2 digit splitting etc.) are a follow-up.

Decoding inverts both: `▁` → space and `<0xNN>` → raw byte for SPM,
the byte remap for BPE; control tokens produce nothing.

## Library API

```nurl
$ `deps/gguf/src/gguf.nu`
$ `src/tokenizer.nu`

: !*Gguf String gr ( gguf_open `model.gguf` )
?? gr {
    T g → {
        : !*Tok String tr ( tok_new g )       // copies the vocab —
        ( gguf_close g )                      // the Gguf can close now
        ?? tr {
            T t → {
                : ( Vec i ) ids ( tok_encode t `hello world` T )
                : ( Vec u ) bytes ( tok_decode t ids )
                ( tok_free t )
            }
            F e → { /* … */ }
        }
    }
    F e → { /* … */ }
}
```

## Verified

- `selftest`: synthetic SPM + BPE vocabularies built with the gguf
  **writer** and parsed back through the real parser, checked against
  hand-derived ids — merge chains, prefix pieces, byte fallback
  (emoji), UNK, empty input, decode round-trips. 17 checks.
- `tests/tokenizer_test.sh` with `NURL_NET_TESTS=1`: token-for-token
  parity with an **independent python SentencePiece implementation**
  on a real llama.cpp model (stories260K) across unicode, emoji,
  whitespace runs and the empty string, plus encode→decode
  round-trips.
- ASan/UBSan/LeakSanitizer clean.
- `tests/infer_test.sh` with `NURL_NET_TESTS=1`: final-position logits
  agree with an **independent numpy implementation** of the forward
  pass (f32 tolerance, identical argmax); a 40-token greedy
  continuation of a real llama.cpp model is **text-identical** to
  numpy's; the CPU backend reproduces the CUDA text exactly; a
  Q4_0+Q8_0 model generates through the dequant load path; seeded
  sampling is deterministic.

## Roadmap

Batched prefill (the prompt currently runs one decode step per token),
fused attention, and per-model BPE pre-tokenizer variants (qwen2). See
the plan in the repo's development notes.
