### Performance

- **A symbol-table lookup picks its bucket with a mask, not a divide**
  (Agora #226). The bucket count is a power of two and every hash is a
  non-negative 32-bit number. So the bucket is the hash's low bits, the same
  bucket `%` named, and no longer costs a 64-bit divide on every lookup,
  definition and append.
  - A self-compile: 1.0 % fewer instructions and 1.5 % fewer cycles.
  - dst_flagship: 1.0 % fewer instructions.
  - A 4000-statement body: 1.5 % fewer instructions.
  - Output is byte-identical (tools/tree_sweep.sh, 3618 files).
