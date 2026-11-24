### Performance

- **The compiler's symbol tables take a third less memory per entry**
  (Agora #973). Six of each entry's per-entry words, previously 8 bytes
  each, are now 4:
  - its scope depth;
  - its bucket-chain link and the bucket heads;
  - its cached value length;
  - its hash, read back zero-extended, so buckets and lookups are
    unchanged;
  - its buffer size.

  A self-compile holds over half a million entries at its peak. On the same
  input:
  - peak RSS drops from 200.6 MB to 183.6 MB (−8.5 %);
  - instructions drop from 27.400 G to 27.353 G (−0.17 %);
  - wall time is unchanged within noise.

  Hash chains compare in 32 bits, so the narrower words cost no extra
  instruction.

  The emitted LLVM is byte-identical across the tree (`tools/tree_sweep.sh`).

  A value length or buffer size of 2 GiB or more now stops the compile
  with a message (`__sym_n32`) rather than being stored wrong. No program
  the compiler can read reaches that size.
