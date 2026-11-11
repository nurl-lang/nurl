# NURL post-quantum crypto peer-comparison

Generated `2026-11-11T18:08:41Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16370920 KiB |
| Commit | `a013bfae93c3f95925d589a5909e374b9705b502` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43074613881 |
| NURL | `v0.91.0-7-ga013bfae` |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 429 MB/s | **473 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **9.8** | 21.9 | 2.25× |
| ML-KEM-512 encaps | **8.9** | 19.8 | 2.24× |
| ML-KEM-512 decaps | **10.3** | 25.3 | 2.45× |
| ML-KEM-768 keygen | **17.8** | 38.1 | 2.14× |
| ML-KEM-768 encaps | **14.3** | 33.5 | 2.34× |
| ML-KEM-768 decaps | **16.5** | 41.2 | 2.50× |
| ML-KEM-1024 keygen | **26.0** | 61.4 | 2.36× |
| ML-KEM-1024 encaps | **20.0** | 52.8 | 2.64× |
| ML-KEM-1024 decaps | **22.8** | 62.5 | 2.74× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **31.3** | 143 | 4.57× |
| ML-DSA-44 sign | **117** | 378 | 3.23× |
| ML-DSA-44 verify | **34.8** | 43.6 | 1.25× |
| ML-DSA-65 keygen | **75.9** | 227 | 2.99× |
| ML-DSA-65 sign | **193** | 544 | 2.82× |
| ML-DSA-65 verify | **54.7** | 59.3 | 1.08× |
| ML-DSA-87 keygen | **78.6** | 351 | 4.46× |
| ML-DSA-87 sign | **217** | 635 | 2.93× |
| ML-DSA-87 verify | **77.9** | 84.0 | 1.08× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **28 089** | 215 692 | 7.68× |
| SLH-DSA-SHAKE-128s sign | **220 443** | 1 623 749 | 7.37× |
| SLH-DSA-SHAKE-128s verify | **397** | 1 534 | 3.86× |
| SLH-DSA-SHAKE-128f keygen | **469** | 3 323 | 7.08× |
| SLH-DSA-SHAKE-128f sign | **13 854** | 77 710 | 5.61× |
| SLH-DSA-SHAKE-128f verify | **1 070** | 4 608 | 4.31× |
| SLH-DSA-SHAKE-192f keygen | **646** | 4 906 | 7.59× |
| SLH-DSA-SHAKE-192f sign | **20 502** | 125 161 | 6.10× |
| SLH-DSA-SHAKE-192f verify | **1 516** | 6 788 | 4.48× |
| SLH-DSA-SHAKE-256f keygen | **1 731** | 12 789 | 7.39× |
| SLH-DSA-SHAKE-256f sign | **37 960** | 257 288 | 6.78× |
| SLH-DSA-SHAKE-256f verify | **1 543** | 6 928 | 4.49× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 9% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (1.08–1.25× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (3.9–7.7×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (1.1–4.6×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
