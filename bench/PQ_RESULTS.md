# NURL post-quantum crypto peer-comparison

Generated `2026-08-22T16:51:53Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `1c6ef287d1269ff973930368e903a885b40d7a38` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32585938403 |
| NURL | `v0.49.0-2-g1c6ef287` |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 453 MB/s | **473 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **16.7** | 24.3 | 1.46× |
| ML-KEM-512 encaps | **16.6** | 21.6 | 1.30× |
| ML-KEM-512 decaps | **20.6** | 27.7 | 1.34× |
| ML-KEM-768 keygen | **26.9** | 41.9 | 1.56× |
| ML-KEM-768 encaps | **24.6** | 36.9 | 1.50× |
| ML-KEM-768 decaps | **31.0** | 44.8 | 1.44× |
| ML-KEM-1024 keygen | **38.7** | 67.3 | 1.74× |
| ML-KEM-1024 encaps | **33.8** | 57.8 | 1.71× |
| ML-KEM-1024 decaps | **40.1** | 70.2 | 1.75× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **38.3** | 146 | 3.81× |
| ML-DSA-44 sign | **126** | 303 | 2.41× |
| ML-DSA-44 verify | 41.9 | **38.3** | 0.91× |
| ML-DSA-65 keygen | **92.4** | 229 | 2.48× |
| ML-DSA-65 sign | **203** | 453 | 2.23× |
| ML-DSA-65 verify | 63.7 | **52.4** | 0.82× |
| ML-DSA-87 keygen | **97.8** | 348 | 3.56× |
| ML-DSA-87 sign | **232** | 537 | 2.31× |
| ML-DSA-87 verify | 97.2 | **73.2** | 0.75× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **41 355** | 225 149 | 5.44× |
| SLH-DSA-SHAKE-128s sign | **308 642** | 1 674 347 | 5.42× |
| SLH-DSA-SHAKE-128s verify | **514** | 1 625 | 3.16× |
| SLH-DSA-SHAKE-128f keygen | **629** | 3 489 | 5.54× |
| SLH-DSA-SHAKE-128f sign | **18 173** | 81 239 | 4.47× |
| SLH-DSA-SHAKE-128f verify | **1 541** | 4 701 | 3.05× |
| SLH-DSA-SHAKE-192f keygen | **950** | 4 954 | 5.22× |
| SLH-DSA-SHAKE-192f sign | **27 632** | 127 899 | 4.63× |
| SLH-DSA-SHAKE-192f verify | **2 107** | 6 963 | 3.30× |
| SLH-DSA-SHAKE-256f keygen | **2 432** | 13 364 | 5.50× |
| SLH-DSA-SHAKE-256f sign | **53 550** | 265 382 | 4.96× |
| SLH-DSA-SHAKE-256f verify | **2 254** | 6 870 | 3.05× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 4% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (0.75–0.91× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (3.0–5.5×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (0.8–3.8×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
