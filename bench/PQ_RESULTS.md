# NURL post-quantum crypto peer-comparison

Generated `2026-11-07T06:13:42Z` by `bench/run_pq.sh`. **Do not edit by hand** — the next run overwrites it.

Single-core µs/op for the three NIST post-quantum standards — ML-KEM (FIPS 203, the KEM in the X25519MLKEM768 hybrid TLS group), ML-DSA (FIPS 204, certificate signatures) and SLH-DSA (FIPS 205, the hash-based fallback) — plus the SHAKE128 bulk throughput they are all built from. NURL is the pure-NURL stdlib (`std/mlkem`, `std/mldsa`, `std/slhdsa`); Rust is the pure-Rust RustCrypto crates. Both sides are portable safe-language implementations with no hand-written assembly, measured by the same harness discipline (iteration-calibrated timed loops, per-op OS randomness, hedged signing, medians of 3 runs). The ratios compare those two implementations, not the two languages — "Where the ratios come from" below says what they do and do not show.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `5ab35366b67fb4619867e1a648b2b02711a093b3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42345938053 |
| NURL | `v0.90.0` |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |

| Implementation | Source |
|---|---|
| NURL | `stdlib/std/{mlkem,mldsa,slhdsa,hash_sha3}.nu`, `./nurl.sh -O2` |
| Rust | RustCrypto `ml-kem 0.3.2`, `ml-dsa 0.1.1`, `slh-dsa 0.2.0-rc.5`, `shake 0.1.0`, `--release` (opt-level 3, fat LTO) |

## SHAKE128 bulk throughput

Every scheme below spends most of its cycles in Keccak; this is the one-shot absorb rate over an 8 MB message (single lane — the multi-lane SIMD Keccak NURL uses inside SLH-DSA shows up in that table instead).

| | NURL | Rust |
|---|---:|---:|
| SHAKE128 absorb 8 MB | 436 MB/s | **473 MB/s** |

## ML-KEM (FIPS 203)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-KEM-512 keygen | **9.9** | 21.9 | 2.22× |
| ML-KEM-512 encaps | **9.0** | 19.8 | 2.20× |
| ML-KEM-512 decaps | **10.4** | 25.8 | 2.48× |
| ML-KEM-768 keygen | **17.8** | 38.2 | 2.14× |
| ML-KEM-768 encaps | **14.7** | 33.1 | 2.26× |
| ML-KEM-768 decaps | **16.7** | 41.2 | 2.47× |
| ML-KEM-1024 keygen | **26.2** | 61.1 | 2.33× |
| ML-KEM-1024 encaps | **20.4** | 52.4 | 2.57× |
| ML-KEM-1024 decaps | **22.9** | 62.9 | 2.74× |

## ML-DSA (FIPS 204)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| ML-DSA-44 keygen | **31.6** | 143 | 4.52× |
| ML-DSA-44 sign | **119** | 350 | 2.95× |
| ML-DSA-44 verify | **35.9** | 43.5 | 1.21× |
| ML-DSA-65 keygen | **75.9** | 227 | 2.99× |
| ML-DSA-65 sign | **192** | 560 | 2.92× |
| ML-DSA-65 verify | **56.2** | 59.1 | 1.05× |
| ML-DSA-87 keygen | **79.0** | 350 | 4.43× |
| ML-DSA-87 sign | **222** | 660 | 2.97× |
| ML-DSA-87 verify | **81.9** | 83.9 | 1.02× |

## SLH-DSA (FIPS 205)

| Operation | NURL µs/op | Rust µs/op | Rust / NURL |
|---|---:|---:|---:|
| SLH-DSA-SHAKE-128s keygen | **38 740** | 216 578 | 5.59× |
| SLH-DSA-SHAKE-128s sign | **215 052** | 1 634 697 | 7.60× |
| SLH-DSA-SHAKE-128s verify | **372** | 1 646 | 4.43× |
| SLH-DSA-SHAKE-128f keygen | **429** | 3 410 | 7.95× |
| SLH-DSA-SHAKE-128f sign | **13 207** | 78 441 | 5.94× |
| SLH-DSA-SHAKE-128f verify | **1 118** | 4 743 | 4.24× |
| SLH-DSA-SHAKE-192f keygen | **689** | 4 897 | 7.11× |
| SLH-DSA-SHAKE-192f sign | **21 640** | 125 614 | 5.80× |
| SLH-DSA-SHAKE-192f verify | **1 586** | 6 751 | 4.26× |
| SLH-DSA-SHAKE-256f keygen | **1 835** | 12 836 | 7.00× |
| SLH-DSA-SHAKE-256f sign | **41 145** | 256 332 | 6.23× |
| SLH-DSA-SHAKE-256f verify | **1 595** | 6 821 | 4.28× |

(Best per row in **bold**. `Rust / NURL` > 1 means NURL is faster. `n/a` = toolchain absent or the harness failed.)

## Where the ratios come from

This table compares two implementations, not two languages. Before quoting a ratio, know what it is made of:

- **Start from the control row.** Single-lane SHAKE128 is the closest thing here to a pure language-and-compiler comparison: the same scalar Keccak permutation, the same workload, no API or vectorisation asymmetry on either side. In this run the two columns are within 8% of each other. Ratios far above that elsewhere are implementation differences, not language ones — compare the ML-DSA verify rows (1.02–1.21× in this run), the least asymmetric scheme-level operations.
- **SLH-DSA (4.2–8.0×): batched Keccak vs scalar Keccak.** SLH-DSA's cost is thousands of short, independent hash chains. NURL batches them four Keccak lanes at a time (`std/hash_sha3x4`: `simd`-prefixed NURL source the compiler vectorises to AVX2 behind a runtime CPU check); RustCrypto `slh-dsa` hashes one lane at a time. No assembly on either side, but these rows compare a batched implementation against a scalar one. A Rust port of the same four-lane strategy (e.g. via `std::simd`) should close most of this gap; no such crate path existed at measurement time.
- **ML-KEM and ML-DSA (1.0–4.5×): a tuned implementation against young crates.** Both columns spend most of these cycles in the same scalar Keccak the control row measures directly, so the gaps live in what surrounds it — sampling, NTT, serialisation, memory traffic. The RustCrypto lattice crates are pre-1.0 and have not had a dedicated performance pass; the NURL stdlib has been profiled and tuned across several releases. These rows have not been root-caused one by one: read them as optimised-vs-not-yet-optimised implementations, with the language contribution bounded by the control row above.
- **Neither column is the fastest known.** The scheme authors' AVX2 assembly implementations beat both columns on the lattice schemes; see the header of `bench/pq.nu` for that comparison.

## Notes

- **Correctness is pinned elsewhere.** Every NURL algorithm here is byte-exact against NIST ACVP vectors (`tools/*_acvp_gate.nu`); this report only measures speed.
- **API-surface caveat (ML-DSA sign).** RustCrypto signs from a pre-expanded signing key (expansion paid once at keygen); NURL's `mldsa_sign` takes the FIPS 204 byte-string secret key and expands per call. The NURL column pays that expansion inside every sign op, the Rust column does not.
- **Randomness.** Keygen, encaps and hedged signing draw per-op OS entropy on both sides (NURL `nurl_rand_fill`, Rust `SysRng`), so the syscall cost is in both columns.
- Single core, loopback-free, allocation costs included. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.
