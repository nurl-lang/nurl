### Performance

- **P-256 ECDH shared is 7 % faster, ECDSA verify 5 %** (Agora #225).
  Every Jacobian doubling does ten modular additions, and their final
  step sat on the doubling's critical path. That step chooses between
  `a + b` and `a + b − p` without a branch. It derived its choice from
  the carry and the borrow through a signed difference, a comparison
  and two masks, and LLVM turned that into a seven-instruction chain
  ending in `cmov`, `and` and `or`.

  The choice now comes from one more borrow, out of the fifth word of
  `(carry : a + b) − p`, and one XOR-AND-XOR per limb picks the result. A
  doubling went from 191 to 175 ns. The mixed addition also forms 2V
  while H³ is still being multiplied, so X3 = R² − H³ − 2V waits on H³
  for two subtractions instead of three.

  Measured on a Sapphire Rapids class Xeon (min of 9, interleaved):

  | Operation | Before | After |
  |---|---|---|
  | ECDH shared | 78.8 µs | 73.1 µs |
  | ECDSA verify | 77.4 µs | 73.3 µs |

  Keygen and sign run the fixed-base comb, which has no doublings, and
  do not change.
