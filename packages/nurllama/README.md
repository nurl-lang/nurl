# nurllama — run language models locally, in pure NURL

The ollama-shaped engine, built package by package on top of
[`packages/gguf`](../gguf) and [`packages/gpu`](../gpu).
**Phase 3 (current): the inference core.**

```
$ nurllama run model.gguf "Once upon a time" -n 40 --temp 0
, there was a little girl named Lily. She loved to play outside in the
park. One day, she saw a big, red ball.

nurllama run model.gguf "prompt" [-n N] [--temp F] [--topk N] [--topp F] [--seed N]
nurllama logits model.gguf "prompt"               # verification tap
nurllama tokenize model.gguf "Once upon a time"   # → 1 403 407 261 378
nurllama detok model.gguf 1 403 407 261 378       # → " Once upon a time"
nurllama vocab model.gguf 10                      # first 10 pieces
nurllama selftest                                 # 17 bit-exact checks
```

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

Phase 4: model store + pull (`~/.nurllama`). Phase 5: CLI chat + an
ollama-compatible HTTP API. Phase 6: device-side dequant-in-matmul,
K-quants, batched prefill. See the plan in the repo's development
notes.
