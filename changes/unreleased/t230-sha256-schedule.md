### Performance

- **SHA-256 without SHA-NI is 16 % faster** (Agora #230). These are hosts
  such as Skylake-SP and Cascade Lake cloud instances; HMAC, HKDF and
  every TLS transcript hash run on it there. The message schedule now
  runs four words at a time on `v128` (SSE2, NEON, or wasm SIMD128,
  whatever the target has), and it runs inside the round loop, eight
  words ahead of the rounds. Its vector work fills the issue slots that
  the rounds' dependency chain leaves idle, and each round reads
  W[t] + K[t] with one load and no add. Maj(a, b, c) is computed as
  b ^ ((a ^ b) & (b ^ c)) with a ^ b carried to the next round, where it
  is b ^ c: one operation fewer a round.

  The rounds themselves already matched aws-lc's under llvm-mca. The
  scalar schedule, run as a separate pass, was the ~3 cycles a round of
  difference. The transform is not marked `simd`: its baseline lowering
  is within 3 % of an x86-64-v3 clone, and a second copy of it would
  make every program that hashes compile slower (measured: unchanged at
  about 400 ms against 460–540 ms with the clone).

  Measured on a Sapphire Rapids class Xeon with `NURL_CPU_SHA=0`, 16 KB
  per hash, best of three interleaved runs:

  | Implementation | Time |
  |---|---|
  | Before | 65.3 µs |
  | After | 54.7 µs |
  | aws-lc, SHA extensions masked | 49.6 µs |

  That is 89–91 % of aws-lc across runs, up from 76 %. CPUs with SHA-NI
  keep their kernel unchanged.
