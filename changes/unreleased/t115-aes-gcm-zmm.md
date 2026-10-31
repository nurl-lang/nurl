### Performance

- **AES-GCM on AVX-512 VAES CPUs: a 16 KB TLS record seals 6–8 % faster,
  and 1 KB or less about 20 % faster** (Agora #115). Ice Lake server,
  Sapphire Rapids and Zen 4/5 run this zmm kernel. The kernel had two
  costs that aws-lc's does not:
  - Sealing read each sixteen-block step's ciphertext back from the
    output buffer for GHASH, a few dozen cycles after storing it. A TLS
    record's payload starts 5 bytes into its buffer, so those 64-byte
    stores straddle two cache lines. A split store cannot forward to a
    load, so every read-back waited for its store to reach L1, and so
    did the final fold after the last step. The ciphertext now stays in
    the four registers that produced it.
  - Each step's GHASH reduction added up all three accumulators' lanes
    and then reduced on xmm, 22 vector operations. It now reduces on all
    four lanes and adds two of them, 16 operations.

    While 512-bit work is in flight, port 1 runs no vector operations,
    so the loop is bound by its vector operations on ports 0 and 5.
    Each one removed saves half a cycle a step.

  Measured on a Sapphire Rapids class Xeon, `aes_gcm_seal_in` with the
  payload 5 bytes into its buffer. Each figure is the best of three
  interleaved runs of seven passes; aws-lc is aws-lc-rs's
  `seal_in_place_separate_tag` on the same layout:

  | Payload | Before | After | aws-lc |
  |---|---|---|---|
  | 256 B | 87 ns | 67 ns | 125 ns |
  | 1 KB | 130 ns | 107 ns | 184 ns |
  | 4 KB | 327 ns | 304 ns | 359 ns |
  | 16 KB | 1 213 ns | 1 116 ns | 1 155 ns |
  | 64 KB | 4 570 ns | 4 441 ns | 4 506 ns |

  In tls-bench on the same host, the AES-128-GCM seal 16 KB row is at
  102 % of aws-lc, and 1 MB bulk over AES-128-GCM is at 110 % of rustls.

  The ymm (VAES) and xmm (AES-NI) kernels are unchanged. New gates:
  - `compiler/tests/aes_gcm_wycheproof` runs Wycheproof's 133 AES-GCM
    cases on the software key and on every hardware tier, sealing both
    into a fresh Vec and in place.
  - `aes_gcm_hw_agree` adds twelve pseudorandom lengths below 64 KiB
    per key size.
  - `crypto_tier_ir.sh` checks that each wide kernel's GHASH is
    VPCLMULQDQ at its own width, and runs the Wycheproof test with each
    tier masked off in turn.
