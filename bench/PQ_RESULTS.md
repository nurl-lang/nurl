# NURL post-quantum crypto peer-comparison

Generated `2026-09-13T12:50:11Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `5e903cd900500580bc215bb0ecdd2dd90f8ea9fd` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34758120723 |
| NURL | `v0.64.0-5-g5e903cd9` |
| Rust | rustc 1.98.1 (48a229cea 2026-09-01) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 356 MB/s | **405 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **18.5** | 26.7 | 1.45× |
| ML-KEM-512 encaps | **20.0** | 24.5 | 1.23× |
| ML-KEM-512 decaps | **24.9** | 31.0 | 1.24× |
| ML-KEM-768 keygen | **29.0** | 46.0 | 1.59× |
| ML-KEM-768 encaps | **29.4** | 42.1 | 1.43× |
| ML-KEM-768 decaps | **36.1** | 51.6 | 1.43× |
| ML-KEM-1024 keygen | **40.8** | 72.9 | 1.79× |
| ML-KEM-1024 encaps | **39.3** | 64.8 | 1.65× |
| ML-KEM-1024 decaps | **47.8** | 77.1 | 1.61× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **44.5** | 163 | 3.66× |
| ML-DSA-44 sign | **149** | 388 | 2.61× |
| ML-DSA-44 verify | **49.2** | 50.4 | 1.02× |
| ML-DSA-65 keygen | **100** | 260 | 2.60× |
| ML-DSA-65 sign | **240** | 658 | 2.74× |
| ML-DSA-65 verify | 76.9 | **68.9** | 0.90× |
| ML-DSA-87 keygen | **112** | 401 | 3.60× |
| ML-DSA-87 sign | **280** | 733 | 2.62× |
| ML-DSA-87 verify | 114 | **95.7** | 0.84× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **43 820** | 244 679 | 5.58× |
| SLH-DSA-SHAKE-128s sign | **331 700** | 1 869 779 | 5.64× |
| SLH-DSA-SHAKE-128s verify | **567** | 1 907 | 3.36× |
| SLH-DSA-SHAKE-128f keygen | **698** | 3 847 | 5.52× |
| SLH-DSA-SHAKE-128f sign | **19 620** | 90 027 | 4.59× |
| SLH-DSA-SHAKE-128f verify | **1 566** | 5 418 | 3.46× |
| SLH-DSA-SHAKE-192f keygen | **1 002** | 5 737 | 5.73× |
| SLH-DSA-SHAKE-192f sign | **30 734** | 143 914 | 4.68× |
| SLH-DSA-SHAKE-192f verify | **2 253** | 7 846 | 3.48× |
| SLH-DSA-SHAKE-256f keygen | **2 632** | 14 981 | 5.69× |
| SLH-DSA-SHAKE-256f sign | **57 939** | 298 202 | 5.15× |
| SLH-DSA-SHAKE-256f verify | **2 318** | 7 923 | 3.42× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 12% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (0.84–1.02× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (3.4–5.7×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (0.8–3.7×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
