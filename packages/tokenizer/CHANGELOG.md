# Changelog

## 0.3.2

Unigram encoding was quadratic in the length of the text, twice over.

- **The Viterbi inner loop no longer copies or re-hashes a substring per
  candidate piece.** For every (start, end) pair on a character boundary
  it built the substring into a scratch `String` and looked that up in a
  `HashMap s i` — a copy, a full re-hash of the copy, and a `strcmp`
  per probe. It now keeps ONE rolling FNV-1a per start position,
  extended a byte at a time as the end advances, and probes an
  open-addressed table that stores each piece's hash beside its id: no
  copy, no re-hash, and a `memcmp` against the raw text only once the
  64-bit hashes already agree. The `HashMap` stays for the cold callers.

  The table interleaves hash and id in ONE array rather than keeping two
  parallel ones. At 250 k pieces it is 8 MB, so every probe is a cache
  miss by construction, and two arrays make it two misses for what fits
  in a single 64-byte line. Interleaving them: sixteen 120-word texts in
  one request, **154 → 101 ms** end to end.

- **The byte accessors in the hot loops are the O(1) ones.** The Viterbi
  scan, the FNV loop, and `uni_encode`'s lstrip/rstrip whitespace walks
  indexed with `nurl_str_get`, which re-runs `strlen` on every call for
  its bounds check — exactly the trap `stdlib/core/string.nu` documents
  above `nurl_str_at`, and exactly as quadratic as it warns. On a
  2000-word text `__strlen_avx2` was **41 % of the whole embedding
  request**, model forward included. Hoisting the length and indexing
  with `nurl_str_at` is the documented fix.

  Together, on a 2000-word text through packages/embed on a 4090:
  tokenize + forward **134 → 76 ms**, of which the forward is 64 ms —
  so tokenizing went from ~70 ms to ~12 ms. Token output is unchanged:
  all 27 lines of the multilingual corpus stay token-identical to
  Hugging Face `tokenizers`, and the ASan pass stays clean.

  Tokenizing is still the largest non-GPU term in an embedding request
  for short-to-medium texts; the remaining cost is the Viterbi's own
  `n × max_piece` probe count, which wants a trie rather than a hash
  table to prune. That is not done here.

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
