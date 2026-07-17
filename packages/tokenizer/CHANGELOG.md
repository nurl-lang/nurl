# Changelog

## 0.3.0

Unigram engine (`src/unigram.nu`) — the Hugging Face tokenizer.json
Unigram family (XLM-RoBERTa, BGE, multilingual-e5, …):

- **Precompiled charsmap normalizer**: the sentencepiece NFKC-style
  replacement table, decoded from the file's base64 blob into a
  darts-clone double-array trie and applied by longest match.
- **Metaspace pre-tokenization** with HF's exact prepend rule (no double
  ▁ when the text already starts with one) and the Replace space-run
  collapse.
- **True Unigram Viterbi** over piece log-probabilities (greedy bigram
  merging does not reproduce it), unknown chars at min_score − 10 with
  consecutive unknowns fused, byte-exact UTF-8 boundary handling.
- **Added-token extraction** on raw text with lstrip/rstrip semantics
  (`<mask>` consumes preceding whitespace) and TemplateProcessing
  `<s> … </s>` ids read from the file.
- API: `uni_load` / `uni_encode` / `uni_free` + vocab accessors.
- `tests/unigram_test.sh`: token-for-token against a committed golden
  produced by Hugging Face `tokenizers` on a 27-line multilingual corpus
  (Latin/CJK/Cyrillic/Arabic, emoji, NFKC ligatures + fullwidth forms,
  whitespace edges, inline specials); ASan/LSan clean.
- Performance work landed in the stdlib while building this: FNV-1a+mix
  `hash_string` (real-world keys probed ~7–20× faster), linear-time
  base64 decode, and `utf8_decode_n` (the strlen-per-byte-access trap) —
  250 002-piece load 3.4 s → 0.24 s, 7 k-token encode 2.4 s → 0.13 s.

## 0.2.0

BPE vocabularies without merges accepted as decode-and-specials
vocabularies (transcriber use). See git history.

## 0.1.x

Initial extraction from nurllama: SentencePiece bigram merging + byte
BPE, GGUF and HF loaders.
