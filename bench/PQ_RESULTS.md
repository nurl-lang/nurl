# NURL post-quantum crypto peer-comparison

Generated `2026-08-20T13:12:24Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `Linux x86_64` |
| Kernel | `Linux 7.0.0-28-generic x86_64` |
| CPU | Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz (12 logical cores) |
| Memory | 32770952 KiB |
| Commit | `d8509c7d81045be34a29554a680f9030ef66c99f` |
| NURL | `v0.45.0-20-g8257c78a-dirty` |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 345 MB/s | **348 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **18.7** | 29.7 | 1.58× |
| ML-KEM-512 encaps | **20.2** | 26.7 | 1.32× |
| ML-KEM-512 decaps | **25.4** | 34.3 | 1.35× |
| ML-KEM-768 keygen | **28.8** | 50.8 | 1.76× |
| ML-KEM-768 encaps | **29.8** | 46.8 | 1.57× |
| ML-KEM-768 decaps | **36.4** | 58.2 | 1.60× |
| ML-KEM-1024 keygen | **42.1** | 80.2 | 1.90× |
| ML-KEM-1024 encaps | **41.2** | 73.2 | 1.78× |
| ML-KEM-1024 decaps | **50.3** | 87.1 | 1.73× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **48.9** | 177 | 3.61× |
| ML-DSA-44 sign | **162** | 439 | 2.71× |
| ML-DSA-44 verify | **49.9** | 51.3 | 1.03× |
| ML-DSA-65 keygen | **97.7** | 288 | 2.94× |
| ML-DSA-65 sign | **262** | 689 | 2.64× |
| ML-DSA-65 verify | 80.4 | **69.9** | 0.87× |
| ML-DSA-87 keygen | **116** | 440 | 3.81× |
| ML-DSA-87 sign | **301** | 660 | 2.19× |
| ML-DSA-87 verify | 124 | **98.9** | 0.80× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **47 170** | 281 027 | 5.96× |
| SLH-DSA-SHAKE-128s sign | **368 241** | 2 116 265 | 5.75× |
| SLH-DSA-SHAKE-128s verify | **526** | 2 153 | 4.09× |
| SLH-DSA-SHAKE-128f keygen | **654** | 4 354 | 6.65× |
| SLH-DSA-SHAKE-128f sign | **20 375** | 101 136 | 4.96× |
| SLH-DSA-SHAKE-128f verify | **1 561** | 6 100 | 3.91× |
| SLH-DSA-SHAKE-192f keygen | **970** | 6 517 | 6.72× |
| SLH-DSA-SHAKE-192f sign | **33 635** | 164 762 | 4.90× |
| SLH-DSA-SHAKE-192f verify | **2 263** | 8 808 | 3.89× |
| SLH-DSA-SHAKE-256f keygen | **2 535** | 16 561 | 6.53× |
| SLH-DSA-SHAKE-256f sign | **64 816** | 336 254 | 5.19× |
| SLH-DSA-SHAKE-256f verify | **2 638** | 8 952 | 3.39× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 1% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (0.80–1.03× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (3.4–6.7×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (0.8–3.8×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
