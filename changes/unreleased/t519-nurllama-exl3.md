### Added

- **nurllama runs EXL3 weights** (Agora #519): exllamav3's trellis
  quantisation (MCG, MUL1 and 3INST codebooks, 1–8 and half-integer bits)
  as a weight type its matvec runs without expanding it, bit-exact against
  exllamav3's own reference on CUDA and the CPU backend.
