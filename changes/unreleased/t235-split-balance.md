### Performance

- **A split build waits on no oversized part** (Agora #235).
  `nurlc --split` cut the function sequence into runs with a fixed
  target, sized from bytes every part repeats anyway (module scope and
  `linkonce_odr` bodies). A run closed only after a function had crossed
  the target, so the first parts kept their overshoot and the last ones
  got what was left. Split 12 ways, the compiler's own module had one
  part of 2.99 MB, holding the 1 MB `gen_call`, and two of 0.64 and
  0.26 MB. The step waited on the large part.

  The target is now the bytes the parts actually share out, recomputed
  as each part opens: what is left over the parts left. A run closes
  before a function when taking it would overshoot more than stopping
  short does. A part that would define nothing is not written: its
  `clang` process helped nothing. The runs stay contiguous in emission
  order.

  The compiler, 12 ways: parts 1.73–2.08 MB, against 0.26–2.99 MB. The
  slowest part's `clang -O2 -flto=thin -c` takes 1.43 s instead of
  2.04 s, and total CPU is unchanged. `nurl.sh -O2 compiler/nurlc.nu`
  (split 12, no cache, 4 cores) takes 21.6–23.4 s instead of
  24.3–26.2 s. The built programs are not slower: the compiler's own
  output and speed are unchanged, and ML-DSA's vectors split 12 ways run
  267 M instructions instead of 297 M.
  `compiler/tests/split_equivalence.sh` now checks that every part
  defines a function of its own, and that no part of the compiler holds
  more than 1.25× the mean unless one function alone is that big.
