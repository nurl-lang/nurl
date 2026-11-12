### Performance

- **Importing generic code costs a third less to compile** (Agora #723). A
  program that imports `HashMap`, `Set`, `Deque` and `BTree` and
  instantiates nothing compiles in 32 % fewer compiler instructions; the
  standard container tests 11–18 % fewer; the compiler's own
  self-compile 1.0 % fewer, with a peak heap no larger. Four things went
  into how nurlc keeps a function body for later:
  - a body's text was built by appending each token to a copy of
    everything before it — quadratic in the body's length, with an
    allocation and a free for each token's own text. One growing buffer
    now, each token's bytes copied once, straight from the source;
  - working out a generic's `inout` / `sink` parameters copied,
    substituted and re-lexed the whole template, body included, to read
    its signature; it reads the signature alone;
  - the name scan stored each generic through a lexer of its own, over a
    copy of the template padded with a line break for every line above
    it; it stores it from the file's own lexer, read again from the
    template's `[`;
  - a lexer's line table is built with `memchr` instead of two loops over
    every byte of the source.
  The text kept for a body is byte for byte what it was, so every program
  compiles to the same IR and the same diagnostics.
