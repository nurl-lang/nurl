### Performance

- **ML-KEM and ML-DSA run their four-way Keccak on AVX-512** (Agora
  #281). `__kf1600x4`, the permutation behind every four-way
  SHAKE128/256 (ML-KEM's matrix and noise, ML-DSA's expansion), is
  `simd v4`. Its x86-64-v4 clone rotates with VPROLQ and folds chi's and
  theta's three-input logic into VPTERNLOGQ, where the AVX2 clone spends
  three instructions per 64-bit rotate. Nine four-way permutations take
  3.4 µs instead of 5.5 µs on a Sapphire Rapids class Xeon. ML-KEM-768
  encaps is 4.5–7 % faster, decaps 3–7 % and keygen 4–5 %, and ML-DSA-65
  sign 6 % (verify and keygen unchanged). AVX2-only CPUs run the same
  code as before.

  The cost is a third clone of the permutation. A program that imports
  `std/mlkem.nu` or `std/mldsa.nu` takes 0.5–2 % more build CPU (median,
  `nurl.sh -O2`, no cache). Agora #287 pays it back by taking the
  SSE2-legalised kernel out of the baseline clone.

- **ML-KEM's noise is one Keccak permutation per four polynomials**
  (Agora #281). PRF_η(s, N) is SHAKE256 of 33 bytes into 64·η. For
  η = 2, every ML-KEM-768 and -1024 stream, that fits one rate block,
  so a group of four now runs through `shake256x4_block` on buffers made
  once per batch. Before, each group built a four-way sponge object, its
  two lane vectors and four nonce vectors. Encaps and decaps are about
  2 % faster, with fewer allocations.

  Together, on the Sapphire Rapids class host: ML-KEM-768 encaps
  17.4 → 15.9 µs (median of interleaved runs; aws-lc 16.2 µs in the same
  runs).
