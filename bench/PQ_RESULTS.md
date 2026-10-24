# NURL post-quantum crypto peer-comparison

Generated `2026-10-24T10:16:00Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `92f437fb7ca1bd1d1f182b0191ae94c1d58c193e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40085092474 |
| NURL | `v0.77.2-40-g92f437fb` |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 438 MB/s | **474 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **11.6** | 23.1 | 2.00× |
| ML-KEM-512 encaps | **10.4** | 20.2 | 1.94× |
| ML-KEM-512 decaps | **11.3** | 25.6 | 2.27× |
| ML-KEM-768 keygen | **19.6** | 39.2 | 1.99× |
| ML-KEM-768 encaps | **15.9** | 33.8 | 2.12× |
| ML-KEM-768 decaps | **17.4** | 40.9 | 2.35× |
| ML-KEM-1024 keygen | **28.4** | 62.3 | 2.19× |
| ML-KEM-1024 encaps | **22.4** | 52.7 | 2.35× |
| ML-KEM-1024 decaps | **24.1** | 62.2 | 2.58× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **34.6** | 144 | 4.15× |
| ML-DSA-44 sign | **119** | 356 | 2.99× |
| ML-DSA-44 verify | **38.5** | 43.8 | 1.14× |
| ML-DSA-65 keygen | **79.7** | 228 | 2.86× |
| ML-DSA-65 sign | **197** | 619 | 3.15× |
| ML-DSA-65 verify | 59.9 | **59.5** | 0.99× |
| ML-DSA-87 keygen | **87.6** | 351 | 4.01× |
| ML-DSA-87 sign | **224** | 578 | 2.59× |
| ML-DSA-87 verify | 90.3 | **83.7** | 0.93× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **40 424** | 212 578 | 5.26× |
| SLH-DSA-SHAKE-128s sign | **268 309** | 1 622 127 | 6.05× |
| SLH-DSA-SHAKE-128s verify | **501** | 1 543 | 3.08× |
| SLH-DSA-SHAKE-128f keygen | **632** | 3 375 | 5.34× |
| SLH-DSA-SHAKE-128f sign | **15 742** | 77 210 | 4.90× |
| SLH-DSA-SHAKE-128f verify | **1 320** | 4 584 | 3.47× |
| SLH-DSA-SHAKE-192f keygen | **835** | 4 844 | 5.80× |
| SLH-DSA-SHAKE-192f sign | **25 021** | 125 220 | 5.00× |
| SLH-DSA-SHAKE-192f verify | **1 863** | 6 756 | 3.63× |
| SLH-DSA-SHAKE-256f keygen | **2 163** | 12 722 | 5.88× |
| SLH-DSA-SHAKE-256f sign | **47 230** | 256 623 | 5.43× |
| SLH-DSA-SHAKE-256f verify | **1 939** | 6 770 | 3.49× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 8% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (0.93–1.14× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (3.1–6.0×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (0.9–4.2×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
