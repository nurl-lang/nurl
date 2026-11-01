### Performance

- **The flag folder finds the registers to fold by search, not byte by
  byte** (Agora #305). When nurlc writes out a function whose flags it
  folds, it used to step through every byte of every line, looking for a `%`
  outside quotes. It now jumps from one `%` or `"` to the next. A
  self-compile takes 0.44 % fewer instructions and dst_flagship 0.2 %
  fewer. Output is byte-identical (tools/tree_sweep.sh, 3618 files).
