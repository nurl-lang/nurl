# tokenizer

The tokenizer that feeds a language model — and it does not care which
file the vocabulary arrived in.

```
nurlpkg install tokenizer
```

```
$ tokenizer encode tokenizer.json "<|startoftranscript|><|en|>Hello there"
50258 50259 15947 456

$ tokenizer decode tokenizer.json 50258 50259 15947 456
Hello there
```

## Three engines, one shape

* **SentencePiece** for llama-family vocabularies: space-escape, highest-
  score adjacent merge in llama.cpp's exact selection order (leftmost on
  ties), `<0xNN>` byte fallback, UNK.
* **byte-level BPE** for gpt2-family ones: the GPT-2 byte→unicode remap,
  the contraction/letter/digit/punct/whitespace pre-split (with the qwen2
  variant), lowest-merge-rank pairing.
* **Unigram** for Hugging Face `tokenizer.json` models (XLM-RoBERTa /
  BGE / multilingual-e5 family, `src/unigram.nu`): the sentencepiece
  Precompiled charsmap normalizer (a darts-clone double-array trie of
  NFKC-style replacements, decoded straight from the file), Metaspace
  pre-tokenization, true Viterbi segmentation over piece
  log-probabilities with fused unknowns, added tokens with lstrip/rstrip
  semantics, and TemplateProcessing specials. Verified token-for-token
  against Hugging Face `tokenizers` on a multilingual corpus:

  ```
  ( uni_load `tokenizer.json` )        → !*Unigram String
  ( uni_encode u `text…` T ids )       → ids incl. <s> … </s>
  ( uni_free u )
  ```

**Special tokens are parsed inline.** A chat template writes
`<|im_start|>` or `<start_of_turn>` into the prompt *as text*, and each
has to come back as its own single id. Tokenised as ordinary pieces they
shred into a dozen tokens and the model answers a question nobody asked.

## Loader-agnostic by construction

`tok_build` takes the **parts** — pieces, scores, token types, merge
rules — so a vocabulary can arrive from anywhere without the engine
learning about file formats:

| where it comes from | who loads it |
|---|---|
| a GGUF's `tokenizer.ggml.*` metadata | nurllama |
| Hugging Face's **`tokenizer.json`** | `src/hf.nu` — whisper, and every HF checkpoint |

### Why `tokenizer.json` and not `vocab.json` + `merges.txt`

Because those four files disagree with each other. In whisper-tiny:

* `<|endoftext|>` (id 50257) is **in `vocab.json`** but is only declared
  special in `special_tokens_map.json`
* `<|startoftranscript|>` (50258) is **in neither** — only in
  `added_tokens.json`
* the timestamp markers `<|0.00|>` … `<|30.00|>` are added tokens with
  **`special: false`**, and still have to tokenise as one id each

`tokenizer.json` says all of it in one place, with an explicit `special`
flag per token, and it is what every HF checkpoint ships. Both loaders
are here, but that is the one to use.

## Proven against HF's own tokenizer

20 strings, whisper's vocabulary, **token for token**: plain text,
leading and trailing whitespace, tabs and newlines, unicode and CJK,
contractions, punctuation, the empty string — and every flavour of
special token. Decoding matches
`decode(skip_special_tokens=True)` exactly.

That oracle earned its keep immediately. It found **two real bugs**:

1. **GPT-2's whitespace rule.** `\s+(?!\S)` comes *before* `\s+`: a run
   of whitespace followed by a non-space gives its **last character
   back**, so the next token starts with it — `" leading"` is one piece,
   not `" "` + `"leading"`. The engine swallowed the whole run, so
   `"  leading spaces"` produced ids no model has ever seen. (The qwen2
   pre-tokenizer always had this rule; the default one did not, and
   nothing noticed until a vocabulary without a merge for the double
   space came along.)
2. **Every added token is matched atomically**, not just the `special`
   ones — which is what makes whisper's timestamps single ids.

The llama and qwen engines are pinned by nurllama's existing parity tests
against independent python SentencePiece and BPE implementations on real
models: those are what prove this package is a faithful extraction and
not a rewrite.

## License

MIT OR Apache-2.0
