### Performance

- **nurlc no longer walks comments and its own output byte by byte**
  (Agora #993).
  - The lexer skips a line comment with `memchr` to the line break. A
    third of the compiler's own source is comments, and every scan pass
    lexes the whole file.
  - The lazy-function scan finds each `@` in the emitted module text with
    `memchr`. It used to step over the tens of megabytes one byte at a
    time.

  On a self-compile (same input), instructions drop from 27.400 G to
  27.046 G (−1.29 %) and wall time by about 3 %. Peak memory is unchanged,
  and the emitted LLVM is byte-identical across the tree.
