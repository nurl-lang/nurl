### Performance

- **A large program no longer makes nurlc's string interner quadratic**
  (Agora #310). For every call site, the compiler recorded why a handle
  might come back out of the call as a whole sentence, `it was passed to
  '<f>', which may hand its handle back as the result`, and interned it:
  one string per callee, kept for the whole compile. The symbol hash reads
  a key's first, middle and last 8 bytes. The callee's name sat between
  those windows, so every callee with a name of the same length got the
  same hash, and the interner's probe for any of them walked one chain.
  - A 20,000-function program spent 52 % of its compile there (one chain
    of 20,002 strings, up to 57,000 slots long).
  - A call now records just the callee's name, and the sentence is built
    only when the borrow checker reports an alias through it.
  - That program now compiles in half the instructions (17.20 G → 8.55 G)
    and 2 MB less peak memory.
  - A self-compile, dst_flagship and a 4000-statement body
    are each 0.03–0.3 % faster.
  - Output and diagnostics are byte-identical (tools/tree_sweep.sh, 3604
    files).
