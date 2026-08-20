# NURL post-quantum crypto peer-comparison

Generated `2026-08-20T13:38:43Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `53fe142455fdfe8ef5663b62157cfbeb286e1159` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32375360082 |
| NURL | `v0.46.0-7-g53fe1424` |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | n/a | **367 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | n/a | 29.7 | n/a |
| ML-KEM-512 encaps | n/a | 26.2 | n/a |
| ML-KEM-512 decaps | n/a | 32.7 | n/a |
| ML-KEM-768 keygen | n/a | 50.6 | n/a |
| ML-KEM-768 encaps | n/a | 43.7 | n/a |
| ML-KEM-768 decaps | n/a | 53.5 | n/a |
| ML-KEM-1024 keygen | n/a | 80.2 | n/a |
| ML-KEM-1024 encaps | n/a | 68.3 | n/a |
| ML-KEM-1024 decaps | n/a | 81.5 | n/a |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | n/a | 181 | n/a |
| ML-DSA-44 sign | n/a | 475 | n/a |
| ML-DSA-44 verify | n/a | 55.0 | n/a |
| ML-DSA-65 keygen | n/a | 286 | n/a |
| ML-DSA-65 sign | n/a | 741 | n/a |
| ML-DSA-65 verify | n/a | 74.8 | n/a |
| ML-DSA-87 keygen | n/a | 445 | n/a |
| ML-DSA-87 sign | n/a | 775 | n/a |
| ML-DSA-87 verify | n/a | 106 | n/a |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | n/a | 275 668 | n/a |
| SLH-DSA-SHAKE-128s sign | n/a | 2 079 535 | n/a |
| SLH-DSA-SHAKE-128s verify | n/a | 2 048 | n/a |
| SLH-DSA-SHAKE-128f keygen | n/a | 4 307 | n/a |
| SLH-DSA-SHAKE-128f sign | n/a | 100 535 | n/a |
| SLH-DSA-SHAKE-128f verify | n/a | 6 059 | n/a |
| SLH-DSA-SHAKE-192f keygen | n/a | 6 248 | n/a |
| SLH-DSA-SHAKE-192f sign | n/a | 159 998 | n/a |
| SLH-DSA-SHAKE-192f verify | n/a | 8 804 | n/a |
| SLH-DSA-SHAKE-256f keygen | n/a | 16 388 | n/a |
| SLH-DSA-SHAKE-256f sign | n/a | 329 485 | n/a |
| SLH-DSA-SHAKE-256f verify | n/a | 8 924 | n/a |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **SLH-DSA: batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA: a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
