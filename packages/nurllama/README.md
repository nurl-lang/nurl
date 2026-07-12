# nurllama — run language models locally, in pure NURL

The ollama-shaped engine, built package by package on top of
[`packages/gguf`](../gguf). **Phase 2 (current): the tokenizer.**

```
nurllama tokenize model.gguf "Once upon a time"   # → 1 424 3520 264 632
nurllama detok model.gguf 1 424 3520 264 632      # → " Once upon a time"
nurllama vocab model.gguf 10                      # first 10 pieces
nurllama selftest                                 # 17 bit-exact checks
```

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

## Roadmap

Phase 3: the inference core on gpukit (dequant-on-device, RMSNorm,
RoPE, causal attention, KV-cache, sampling). Phase 4: model store +
pull (`~/.nurllama`). Phase 5: CLI chat + an ollama-compatible HTTP
API. See the plan in the repo's development notes.
