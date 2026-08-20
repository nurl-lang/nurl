# NURL post-quantum crypto peer-comparison

Generated `2026-08-20T11:11:13Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs).

## Environment

| Item | Value |
|---|---|
| Host | `Linux x86_64` |
| Kernel | `Linux 7.0.0-28-generic x86_64` |
| CPU | Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz (12 logical cores) |
| Memory | 32770952 KiB |
| Commit | `3a6bb8fbe79bb466f0ac9a4d40bdbc0e493a34d5` |
| NURL | `v0.45.0-23-g21ad5f25-dirty` |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | **354 MB/s** | 350 MB/s |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **18.7** | 29.8 | 1.59× |
| ML-KEM-512 encaps | **20.2** | 28.2 | 1.40× |
| ML-KEM-512 decaps | **25.3** | 35.1 | 1.39× |
| ML-KEM-768 keygen | **29.6** | 50.6 | 1.71× |
| ML-KEM-768 encaps | **29.9** | 47.1 | 1.58× |
| ML-KEM-768 decaps | **36.6** | 58.6 | 1.60× |
| ML-KEM-1024 keygen | **41.8** | 80.9 | 1.93× |
| ML-KEM-1024 encaps | **41.1** | 73.5 | 1.79× |
| ML-KEM-1024 decaps | **49.9** | 86.9 | 1.74× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **45.6** | 176 | 3.86× |
| ML-DSA-44 sign | **157** | 404 | 2.58× |
| ML-DSA-44 verify | **50.2** | 51.1 | 1.02× |
| ML-DSA-65 keygen | **98.4** | 284 | 2.88× |
| ML-DSA-65 sign | **266** | 600 | 2.26× |
| ML-DSA-65 verify | 87.2 | **70.3** | 0.81× |
| ML-DSA-87 keygen | **125** | 448 | 3.58× |
| ML-DSA-87 sign | **305** | 745 | 2.45× |
| ML-DSA-87 verify | 129 | **99.6** | 0.77× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **39 981** | 281 113 | 7.03× |
| SLH-DSA-SHAKE-128s sign | **331 650** | 2 140 089 | 6.45× |
| SLH-DSA-SHAKE-128s verify | **570** | 2 023 | 3.55× |
| SLH-DSA-SHAKE-128f keygen | **697** | 4 423 | 6.34× |
| SLH-DSA-SHAKE-128f sign | **18 885** | 103 870 | 5.50× |
| SLH-DSA-SHAKE-128f verify | **1 572** | 6 172 | 3.93× |
| SLH-DSA-SHAKE-192f keygen | **966** | 6 491 | 6.72× |
| SLH-DSA-SHAKE-192f sign | **36 021** | 164 480 | 4.57× |
| SLH-DSA-SHAKE-192f verify | **2 314** | 8 988 | 3.89× |
| SLH-DSA-SHAKE-256f keygen | **2 888** | 16 807 | 5.82× |
| SLH-DSA-SHAKE-256f sign | **63 674** | 338 902 | 5.32× |
| SLH-DSA-SHAKE-256f verify | **2 459** | 8 783 | 3.57× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **Both sides are portable code.** No hand-written assembly on either side. NURL's edge in SLH-DSA comes from running four independent Keccak lanes at a time through `std/hash_sha3x4` behind the `simd` prefix — same source language, vectorised by the compiler. The scheme authors' AVX2 implementations are faster than both sides on the lattice schemes; see the header of `bench/pq.nu` for that comparison.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
