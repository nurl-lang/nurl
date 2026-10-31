### Performance

- **SHA-256 runs on ARMv8's SHA-256 instructions on AArch64** (Agora
  #102). Graviton, Ampere, Apple and the other ARMv8 cores with the
  Cryptographic Extension ran the portable rounds. They now run 16
  SHA256H / SHA256H2 pairs and 12 + 12 SHA256SU0 / SU1 a block, through
  `__sha256_blocks_ce`. HMAC-SHA-256, HKDF and every TLS transcript hash
  on such a host go through it. `sha256_cpu_tier` says `armv8-sha2`
  there, and `NURL_CPU_SHA=0` takes it away as it takes SHA-NI away on
  x86-64. x86-64 builds are unchanged: the AArch64 kernel's call folds
  away there, so it costs their build nothing.

### Added

- **AArch64 SHA-256 primitives** (Agora #102): `nurl_v128_sha256h`,
  `_sha256h2`, `_sha256su0` and `_sha256su1`, with ARM's semantics
  (docs/spec.md, the crypto tier table). They are compiled with
  `+neon,+sha2` and gated on the new runtime probe `nurl_cpu_arm_sha2`
  (HWCAP_SHA2 / FEAT_SHA256), and asked through `nurl_cpu_has_sha_arm`,
  a constant false off AArch64. Intel's SHA primitives keep
  `nurl_cpu_has_sha`, which is a constant false on AArch64.
  `compiler/tests/crypto_tier_ir.sh` checks the kernel's IR, its
  machine code and, under qemu-aarch64 where a host has it, its output
  against `sha256_tier_agree`'s golden, with and without
  `NURL_CPU_SHA=0`.
