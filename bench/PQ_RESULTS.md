# NURL post-quantum crypto peer-comparison

Generated `2026-08-29T13:25:31Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `900a240928022084e35cb856078748bc34f5cd51` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33254957326 |
| NURL | `v0.55.0-6-g900a2409` |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 424 MB/s | **472 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **15.3** | 23.0 | 1.51× |
| ML-KEM-512 encaps | **15.1** | 20.4 | 1.35× |
| ML-KEM-512 decaps | **18.2** | 25.6 | 1.40× |
| ML-KEM-768 keygen | **23.9** | 39.9 | 1.67× |
| ML-KEM-768 encaps | **22.2** | 34.8 | 1.57× |
| ML-KEM-768 decaps | **26.5** | 42.5 | 1.60× |
| ML-KEM-1024 keygen | **33.8** | 62.7 | 1.85× |
| ML-KEM-1024 encaps | **29.8** | 53.4 | 1.79× |
| ML-KEM-1024 decaps | **35.4** | 63.4 | 1.79× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **35.1** | 142 | 4.05× |
| ML-DSA-44 sign | **109** | 357 | 3.27× |
| ML-DSA-44 verify | **37.5** | 43.2 | 1.15× |
| ML-DSA-65 keygen | **80.0** | 225 | 2.82× |
| ML-DSA-65 sign | **170** | 618 | 3.63× |
| ML-DSA-65 verify | **58.1** | 58.8 | 1.01× |
| ML-DSA-87 keygen | **87.8** | 347 | 3.95× |
| ML-DSA-87 sign | **202** | 582 | 2.88× |
| ML-DSA-87 verify | 86.2 | **82.9** | 0.96× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **37 482** | 213 826 | 5.70× |
| SLH-DSA-SHAKE-128s sign | **271 118** | 1 614 916 | 5.96× |
| SLH-DSA-SHAKE-128s verify | **468** | 1 575 | 3.36× |
| SLH-DSA-SHAKE-128f keygen | **555** | 3 318 | 5.97× |
| SLH-DSA-SHAKE-128f sign | **15 854** | 77 616 | 4.90× |
| SLH-DSA-SHAKE-128f verify | **1 290** | 4 542 | 3.52× |
| SLH-DSA-SHAKE-192f keygen | **809** | 4 859 | 6.01× |
| SLH-DSA-SHAKE-192f sign | **25 813** | 125 191 | 4.85× |
| SLH-DSA-SHAKE-192f verify | **2 153** | 6 687 | 3.11× |
| SLH-DSA-SHAKE-256f keygen | **2 500** | 12 758 | 5.10× |
| SLH-DSA-SHAKE-256f sign | **50 819** | 254 778 | 5.01× |
| SLH-DSA-SHAKE-256f verify | **1 924** | 6 851 | 3.56× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 10% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (0.96–1.15× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (3.1–6.0×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (1.0–4.1×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
