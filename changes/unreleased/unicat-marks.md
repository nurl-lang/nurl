### Added

- **`uc_is_mark`: Unicode general category M** (stdlib/std/unicat.nu):
  combining marks, vowel signs and enclosing marks (Mn, Mc, Me). The
  Qwen3.5 and Qwen3.8 pre-tokenizer reads `[\p{L}\p{M}]+` as a word, so a
  tokenizer that knows only letters cuts a Devanagari or accented word at
  every mark (the tokenizer package's `PRE_QWEN35`).

### Changed

- stdlib/std/unicat.nu's categories come from Unicode 15.0.0, not 14.0.0,
  so letters and numbers assigned in 15.0 count as such.
  `tools/gen_unicat.py` generates the mark table with the others.
