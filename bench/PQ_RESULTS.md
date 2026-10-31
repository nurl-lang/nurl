# NURL post-quantum crypto peer-comparison

Generated `2026-10-26T09:47:22Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `d216fa60484e7af06b58883c02fd606856134080` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40302031415 |
| NURL | `v0.78.0-12-gd216fa60` |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 377 MB/s | **400 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **13.3** | 26.6 | 2.01× |
| ML-KEM-512 encaps | **12.4** | 23.4 | 1.90× |
| ML-KEM-512 decaps | **13.7** | 30.0 | 2.19× |
| ML-KEM-768 keygen | **22.8** | 45.4 | 2.00× |
| ML-KEM-768 encaps | **18.9** | 40.5 | 2.14× |
| ML-KEM-768 decaps | **21.1** | 50.0 | 2.37× |
| ML-KEM-1024 keygen | **32.6** | 72.6 | 2.23× |
| ML-KEM-1024 encaps | **26.7** | 63.5 | 2.38× |
| ML-KEM-1024 decaps | **29.5** | 75.3 | 2.55× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **43.5** | 166 | 3.81× |
| ML-DSA-44 sign | **157** | 371 | 2.37× |
| ML-DSA-44 verify | **47.4** | 51.6 | 1.09× |
| ML-DSA-65 keygen | **95.9** | 264 | 2.76× |
| ML-DSA-65 sign | **244** | 666 | 2.73× |
| ML-DSA-65 verify | 74.7 | **69.4** | 0.93× |
| ML-DSA-87 keygen | **107** | 408 | 3.80× |
| ML-DSA-87 sign | **292** | 703 | 2.41× |
| ML-DSA-87 verify | 110 | **98.0** | 0.89× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **41 127** | 246 282 | 5.99× |
| SLH-DSA-SHAKE-128s sign | **306 996** | 1 871 437 | 6.10× |
| SLH-DSA-SHAKE-128s verify | **527** | 1 838 | 3.49× |
| SLH-DSA-SHAKE-128f keygen | **617** | 3 829 | 6.20× |
| SLH-DSA-SHAKE-128f sign | **18 039** | 89 795 | 4.98× |
| SLH-DSA-SHAKE-128f verify | **1 514** | 5 365 | 3.54× |
| SLH-DSA-SHAKE-192f keygen | **928** | 5 608 | 6.04× |
| SLH-DSA-SHAKE-192f sign | **29 173** | 144 295 | 4.95× |
| SLH-DSA-SHAKE-192f verify | **2 195** | 7 580 | 3.45× |
| SLH-DSA-SHAKE-256f keygen | **2 485** | 14 991 | 6.03× |
| SLH-DSA-SHAKE-256f sign | **55 220** | 299 621 | 5.43× |
| SLH-DSA-SHAKE-256f verify | **2 246** | 7 946 | 3.54× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 6% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (0.89–1.09× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (3.5–6.2×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (0.9–3.8×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
