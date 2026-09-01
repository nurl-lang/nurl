# NURL post-quantum crypto peer-comparison

Generated `2026-09-01T08:40:53Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `8f152ab387c490af7a940fad74212638ceb1a61d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33488203126 |
| NURL | `v0.57.0-15-g8f152ab3` |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 328 MB/s | **368 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **19.5** | 29.5 | 1.51× |
| ML-KEM-512 encaps | **19.3** | 25.6 | 1.32× |
| ML-KEM-512 decaps | **23.3** | 32.3 | 1.38× |
| ML-KEM-768 keygen | **30.9** | 50.7 | 1.64× |
| ML-KEM-768 encaps | **29.0** | 44.5 | 1.54× |
| ML-KEM-768 decaps | **34.1** | 54.3 | 1.59× |
| ML-KEM-1024 keygen | **43.9** | 80.1 | 1.83× |
| ML-KEM-1024 encaps | **39.2** | 68.4 | 1.75× |
| ML-KEM-1024 decaps | **45.8** | 80.9 | 1.77× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **44.0** | 181 | 4.11× |
| ML-DSA-44 sign | **139** | 456 | 3.28× |
| ML-DSA-44 verify | **47.1** | 55.2 | 1.17× |
| ML-DSA-65 keygen | **103** | 287 | 2.80× |
| ML-DSA-65 sign | **221** | 662 | 3.00× |
| ML-DSA-65 verify | **74.4** | 75.0 | 1.01× |
| ML-DSA-87 keygen | **112** | 443 | 3.96× |
| ML-DSA-87 sign | **255** | 800 | 3.14× |
| ML-DSA-87 verify | 111 | **106** | 0.95× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **46 638** | 275 100 | 5.90× |
| SLH-DSA-SHAKE-128s sign | **383 695** | 2 072 398 | 5.40× |
| SLH-DSA-SHAKE-128s verify | **591** | 1 994 | 3.37× |
| SLH-DSA-SHAKE-128f keygen | **724** | 4 243 | 5.86× |
| SLH-DSA-SHAKE-128f sign | **20 170** | 99 521 | 4.93× |
| SLH-DSA-SHAKE-128f verify | **1 811** | 6 105 | 3.37× |
| SLH-DSA-SHAKE-192f keygen | **1 048** | 6 320 | 6.03× |
| SLH-DSA-SHAKE-192f sign | **31 526** | 161 935 | 5.14× |
| SLH-DSA-SHAKE-192f verify | **2 369** | 8 726 | 3.68× |
| SLH-DSA-SHAKE-256f keygen | **2 716** | 16 588 | 6.11× |
| SLH-DSA-SHAKE-256f sign | **60 340** | 331 920 | 5.50× |
| SLH-DSA-SHAKE-256f verify | **2 479** | 8 865 | 3.58× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 11% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (0.95–1.17× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (3.4–6.1×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (1.0–4.1×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
