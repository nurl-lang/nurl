### Changed

- **The lexer no longer copies a token's text to the heap** (Agora #236).
  Every token got a freshly allocated copy of its spelling, written into
  the token window and freed again when the slot was reused: `(`, `:`,
  `+` and every name alike. That was about a third of the lexer's time.
  Now a fixed spelling (an operator, a bracket, `→`) points at a literal,
  and a name's text is its own span of the source, copied only when the
  parser asks for it. Only numbers, string literals and merged `a::b`
  names still own text. The self-compile runs 2.1 % fewer instructions,
  `nurlapi/main.nu` 1.9 % and a closure-heavy file 3.2 %, with
  byte-identical output.
