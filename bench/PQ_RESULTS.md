# NURL post-quantum crypto peer-comparison

Generated `2026-10-20T05:42:44Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `df213fb80d7791da9e873413c2851a28b7880018` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39376228125 |
| NURL | `v0.74.0-5-gdf213fb8` |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 437 MB/s | **473 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **14.9** | 23.0 | 1.55× |
| ML-KEM-512 encaps | **15.2** | 20.0 | 1.32× |
| ML-KEM-512 decaps | **18.6** | 25.0 | 1.34× |
| ML-KEM-768 keygen | **23.5** | 39.2 | 1.66× |
| ML-KEM-768 encaps | **22.8** | 34.3 | 1.50× |
| ML-KEM-768 decaps | **28.4** | 41.5 | 1.46× |
| ML-KEM-1024 keygen | **33.3** | 62.1 | 1.86× |
| ML-KEM-1024 encaps | **30.6** | 52.9 | 1.73× |
| ML-KEM-1024 decaps | **37.5** | 62.9 | 1.68× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **34.7** | 144 | 4.14× |
| ML-DSA-44 sign | **110** | 348 | 3.16× |
| ML-DSA-44 verify | **40.4** | 43.6 | 1.08× |
| ML-DSA-65 keygen | **84.3** | 228 | 2.71× |
| ML-DSA-65 sign | **171** | 634 | 3.72× |
| ML-DSA-65 verify | 60.7 | **59.2** | 0.98× |
| ML-DSA-87 keygen | **90.7** | 350 | 3.86× |
| ML-DSA-87 sign | **207** | 690 | 3.34× |
| ML-DSA-87 verify | 87.1 | **83.7** | 0.96× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **35 801** | 214 905 | 6.00× |
| SLH-DSA-SHAKE-128s sign | **268 851** | 1 613 413 | 6.00× |
| SLH-DSA-SHAKE-128s verify | **466** | 1 548 | 3.32× |
| SLH-DSA-SHAKE-128f keygen | **561** | 3 364 | 6.00× |
| SLH-DSA-SHAKE-128f sign | **15 771** | 78 043 | 4.95× |
| SLH-DSA-SHAKE-128f verify | **1 434** | 4 576 | 3.19× |
| SLH-DSA-SHAKE-192f keygen | **905** | 4 936 | 5.45× |
| SLH-DSA-SHAKE-192f sign | **25 530** | 125 867 | 4.93× |
| SLH-DSA-SHAKE-192f verify | **1 894** | 6 940 | 3.66× |
| SLH-DSA-SHAKE-256f keygen | **2 171** | 12 806 | 5.90× |
| SLH-DSA-SHAKE-256f sign | **51 864** | 256 228 | 4.94× |
| SLH-DSA-SHAKE-256f verify | **2 045** | 6 798 | 3.32× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 8% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (0.96–1.08× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (3.2–6.0×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (1.0–4.1×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
