# NURL post-quantum crypto peer-comparison

Generated `2026-10-09T17:38:55Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `dd0104dbfa71691fddb49155e3ecaf66bf5e30c8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37967594304 |
| NURL | `v0.71.0-15-gdd0104db` |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | **410 MB/s** | 404 MB/s |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **18.4** | 26.9 | 1.46× |
| ML-KEM-512 encaps | **18.7** | 23.6 | 1.26× |
| ML-KEM-512 decaps | **23.4** | 30.7 | 1.32× |
| ML-KEM-768 keygen | **29.1** | 46.3 | 1.59× |
| ML-KEM-768 encaps | **28.3** | 40.7 | 1.44× |
| ML-KEM-768 decaps | **34.5** | 50.6 | 1.47× |
| ML-KEM-1024 keygen | **43.2** | 74.6 | 1.73× |
| ML-KEM-1024 encaps | **38.8** | 63.7 | 1.64× |
| ML-KEM-1024 decaps | **47.1** | 76.1 | 1.62× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **45.0** | 165 | 3.68× |
| ML-DSA-44 sign | **146** | 334 | 2.28× |
| ML-DSA-44 verify | 48.1 | **44.0** | 0.91× |
| ML-DSA-65 keygen | **109** | 265 | 2.42× |
| ML-DSA-65 sign | **246** | 560 | 2.27× |
| ML-DSA-65 verify | 77.4 | **59.8** | 0.77× |
| ML-DSA-87 keygen | **117** | 403 | 3.44× |
| ML-DSA-87 sign | **278** | 631 | 2.27× |
| ML-DSA-87 verify | 114 | **84.3** | 0.74× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **48 239** | 243 342 | 5.04× |
| SLH-DSA-SHAKE-128s sign | **367 848** | 1 856 598 | 5.05× |
| SLH-DSA-SHAKE-128s verify | **598** | 1 740 | 2.91× |
| SLH-DSA-SHAKE-128f keygen | **726** | 3 803 | 5.24× |
| SLH-DSA-SHAKE-128f sign | **20 786** | 88 846 | 4.27× |
| SLH-DSA-SHAKE-128f verify | **1 782** | 5 157 | 2.89× |
| SLH-DSA-SHAKE-192f keygen | **1 127** | 5 556 | 4.93× |
| SLH-DSA-SHAKE-192f sign | **32 655** | 142 612 | 4.37× |
| SLH-DSA-SHAKE-192f verify | **2 452** | 7 743 | 3.16× |
| SLH-DSA-SHAKE-256f keygen | **2 905** | 14 697 | 5.06× |
| SLH-DSA-SHAKE-256f sign | **62 218** | 292 661 | 4.70× |
| SLH-DSA-SHAKE-256f verify | **2 565** | 8 035 | 3.13× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 1% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (0.74–0.91× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (2.9–5.2×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (0.7–3.7×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
