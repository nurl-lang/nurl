### Performance

- **A split build inlines the small accessors a one-module build does**
  (Agora #527). Under `--split` each part goes through ThinLTO on its own,
  and a function a part imports cannot be inlined there: the IR mover
  remaps its struct types, and LLVM never inlines a call whose type
  differs from its callee's. The splitter gives a part its own copy of a
  small function to avoid that call, but it measured a function's size
  including the padding, comments and drop-flag bookkeeping the writer
  folds away. So `vec_get` measured 1833 bytes against a 1600-byte limit
  when only 1491 of them were code, and it was never copied. A JPEG
  codec's IDCT made 24 calls to it per block, and a split build decoded
  1.6× slower than a one-module build. Now the size counts only code
  lines. JPEG decode, split: 74 → 47.5 ms with clang and 85 → 49 ms with
  Zig (one module: 46.6 ms). The cost is more copies: building anomaly
  takes about 4 % more wall time and 5 % more CPU, and its binary is 2.9 %
  larger. `split_equivalence.sh` now checks that every part that calls
  `vec_get` or `vec_put_loc` defines it (`split_small_accessor.nu`).
