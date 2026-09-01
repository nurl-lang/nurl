# NURL post-quantum crypto peer-comparison

Generated `2026-09-01T06:04:08Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `9f38b68c42f487345ef0d6847c9c60e2f42a75b5` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33475955362 |
| NURL | `v0.57.0-12-g9f38b68c` |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 362 MB/s | **405 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **17.7** | 26.8 | 1.51× |
| ML-KEM-512 encaps | **18.4** | 24.2 | 1.32× |
| ML-KEM-512 decaps | **22.7** | 30.6 | 1.34× |
| ML-KEM-768 keygen | **28.0** | 46.2 | 1.65× |
| ML-KEM-768 encaps | **27.4** | 41.6 | 1.52× |
| ML-KEM-768 decaps | **33.4** | 51.0 | 1.53× |
| ML-KEM-1024 keygen | **39.7** | 72.8 | 1.83× |
| ML-KEM-1024 encaps | **36.7** | 63.6 | 1.73× |
| ML-KEM-1024 decaps | **44.1** | 75.1 | 1.70× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **43.4** | 162 | 3.74× |
| ML-DSA-44 sign | **139** | 401 | 2.89× |
| ML-DSA-44 verify | **47.5** | 50.8 | 1.07× |
| ML-DSA-65 keygen | **98.9** | 259 | 2.62× |
| ML-DSA-65 sign | **237** | 624 | 2.64× |
| ML-DSA-65 verify | 75.0 | **69.3** | 0.92× |
| ML-DSA-87 keygen | **110** | 404 | 3.66× |
| ML-DSA-87 sign | **272** | 716 | 2.63× |
| ML-DSA-87 verify | 113 | **97.2** | 0.86× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **40 231** | 244 584 | 6.08× |
| SLH-DSA-SHAKE-128s sign | **304 753** | 1 868 828 | 6.13× |
| SLH-DSA-SHAKE-128s verify | **524** | 1 821 | 3.47× |
| SLH-DSA-SHAKE-128f keygen | **641** | 3 849 | 6.01× |
| SLH-DSA-SHAKE-128f sign | **18 063** | 89 559 | 4.96× |
| SLH-DSA-SHAKE-128f verify | **1 473** | 5 248 | 3.56× |
| SLH-DSA-SHAKE-192f keygen | **921** | 5 683 | 6.17× |
| SLH-DSA-SHAKE-192f sign | **28 498** | 144 706 | 5.08× |
| SLH-DSA-SHAKE-192f verify | **2 157** | 7 714 | 3.58× |
| SLH-DSA-SHAKE-256f keygen | **2 447** | 14 842 | 6.07× |
| SLH-DSA-SHAKE-256f sign | **53 267** | 296 217 | 5.56× |
| SLH-DSA-SHAKE-256f verify | **2 189** | 8 020 | 3.66× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 11% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (0.86–1.07× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (3.5–6.2×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (0.9–3.7×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
