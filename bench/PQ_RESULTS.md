# NURL post-quantum crypto peer-comparison

Generated `2026-10-19T20:47:44Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `96d5a4e226dc8d0aaa56f520d8aa78419195dc7c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39322047429 |
| NURL | `v0.73.0-12-g96d5a4e2` |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 381 MB/s | **402 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **17.4** | 26.5 | 1.52× |
| ML-KEM-512 encaps | **18.5** | 23.8 | 1.28× |
| ML-KEM-512 decaps | **23.2** | 30.5 | 1.31× |
| ML-KEM-768 keygen | **27.5** | 45.6 | 1.66× |
| ML-KEM-768 encaps | **28.1** | 40.0 | 1.42× |
| ML-KEM-768 decaps | **34.5** | 49.7 | 1.44× |
| ML-KEM-1024 keygen | **39.4** | 72.4 | 1.83× |
| ML-KEM-1024 encaps | **38.0** | 63.1 | 1.66× |
| ML-KEM-1024 decaps | **46.2** | 75.4 | 1.63× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **42.5** | 166 | 3.90× |
| ML-DSA-44 sign | **140** | 382 | 2.72× |
| ML-DSA-44 verify | **47.8** | 51.7 | 1.08× |
| ML-DSA-65 keygen | **96.3** | 269 | 2.79× |
| ML-DSA-65 sign | **238** | 700 | 2.94× |
| ML-DSA-65 verify | 75.4 | **69.6** | 0.92× |
| ML-DSA-87 keygen | **110** | 410 | 3.73× |
| ML-DSA-87 sign | **270** | 755 | 2.80× |
| ML-DSA-87 verify | 110 | **98.3** | 0.89× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **44 091** | 248 597 | 5.64× |
| SLH-DSA-SHAKE-128s sign | **319 998** | 1 874 922 | 5.86× |
| SLH-DSA-SHAKE-128s verify | **560** | 1 819 | 3.25× |
| SLH-DSA-SHAKE-128f keygen | **688** | 3 861 | 5.62× |
| SLH-DSA-SHAKE-128f sign | **18 681** | 90 225 | 4.83× |
| SLH-DSA-SHAKE-128f verify | **1 550** | 5 400 | 3.48× |
| SLH-DSA-SHAKE-192f keygen | **967** | 5 599 | 5.79× |
| SLH-DSA-SHAKE-192f sign | **29 306** | 144 413 | 4.93× |
| SLH-DSA-SHAKE-192f verify | **2 228** | 7 795 | 3.50× |
| SLH-DSA-SHAKE-256f keygen | **2 564** | 15 079 | 5.88× |
| SLH-DSA-SHAKE-256f sign | **55 544** | 299 985 | 5.40× |
| SLH-DSA-SHAKE-256f verify | **2 278** | 8 037 | 3.53× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 5% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (0.89–1.08× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (3.2–5.9×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (0.9–3.9×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
