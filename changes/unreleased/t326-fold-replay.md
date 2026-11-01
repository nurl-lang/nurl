### Performance

- **The flag folder reads a function's text once, however many rounds it
  takes** (Agora #326). When a round settles a flag to a constant, the
  loads it folds can settle further flags, so the folder runs again. Each
  round re-read the whole function: 2,630 of dst_flagship's functions,
  12.7 MB of IR, were read a second time. The first round now keeps what
  the later ones need: the lines whose value read a register not yet
  known to be constant, the live stores of such a value, and the loads of
  each flag. A later round restores the flags as the first round left
  them and re-evaluates only those lines.
  - dst_flagship compiles in 3.0 % fewer instructions.
  - Output is byte-identical (tools/tree_sweep.sh, 3672 files).
