# NURL post-quantum crypto peer-comparison

Generated `2026-11-13T20:32:14Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `ab45d9db114a58fdab60f618c679e8af95643b5d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43502000834 |
| NURL | `v0.91.1-112-gab45d9db` |
| Rust | rustc 1.100.0 (0ef1bc386 2026-11-09) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 375 MB/s | **405 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **12.0** | 25.7 | 2.14× |
| ML-KEM-512 encaps | **11.3** | 23.5 | 2.07× |
| ML-KEM-512 decaps | **13.2** | 30.5 | 2.31× |
| ML-KEM-768 keygen | **21.1** | 44.9 | 2.13× |
| ML-KEM-768 encaps | **17.7** | 40.1 | 2.26× |
| ML-KEM-768 decaps | **20.3** | 49.7 | 2.45× |
| ML-KEM-1024 keygen | **30.8** | 71.5 | 2.32× |
| ML-KEM-1024 encaps | **25.2** | 62.6 | 2.49× |
| ML-KEM-1024 decaps | **28.4** | 74.3 | 2.62× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **40.9** | 164 | 4.01× |
| ML-DSA-44 sign | **156** | 403 | 2.58× |
| ML-DSA-44 verify | **45.3** | 51.2 | 1.13× |
| ML-DSA-65 keygen | **95.4** | 262 | 2.74× |
| ML-DSA-65 sign | **242** | 592 | 2.44× |
| ML-DSA-65 verify | 70.9 | **68.0** | 0.96× |
| ML-DSA-87 keygen | **105** | 407 | 3.86× |
| ML-DSA-87 sign | **280** | 789 | 2.82× |
| ML-DSA-87 verify | 104 | **96.3** | 0.92× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **42 486** | 245 531 | 5.78× |
| SLH-DSA-SHAKE-128s sign | **316 034** | 1 859 611 | 5.88× |
| SLH-DSA-SHAKE-128s verify | **567** | 1 857 | 3.27× |
| SLH-DSA-SHAKE-128f keygen | **699** | 3 842 | 5.49× |
| SLH-DSA-SHAKE-128f sign | **18 836** | 90 884 | 4.82× |
| SLH-DSA-SHAKE-128f verify | **1 611** | 5 356 | 3.32× |
| SLH-DSA-SHAKE-192f keygen | **981** | 5 689 | 5.80× |
| SLH-DSA-SHAKE-192f sign | **29 486** | 145 641 | 4.94× |
| SLH-DSA-SHAKE-192f verify | **2 268** | 7 782 | 3.43× |
| SLH-DSA-SHAKE-256f keygen | **2 596** | 14 888 | 5.74× |
| SLH-DSA-SHAKE-256f sign | **56 048** | 299 157 | 5.34× |
| SLH-DSA-SHAKE-256f verify | **2 323** | 7 955 | 3.42× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 7% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (0.92–1.13× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (3.3–5.9×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (0.9–4.0×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
