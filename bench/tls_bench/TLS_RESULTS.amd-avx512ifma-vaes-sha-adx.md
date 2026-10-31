# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `amd-avx512ifma-vaes-sha-adx`

Generated `2026-10-31T09:00:34Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `AMD EPYC 9V74 80-Core Processor`, commit `d390e6e3c5ec`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/41186587658). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `amd-avx512ifma-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 545 µs | 460 µs | 84 % | behind |  |
| 2 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,186/s | 2,571/s | 85 % | behind | server CPU 456 vs 388 µs/handshake: of the 68.0 µs gap, 65.4 µs is primitive crypto (largest: RSA-2048 PSS sign, +63.3 µs), 2.65 µs is protocol / runtime / I/O |
| 3 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 298 µs | 271 µs | 91 % | behind |  |
| 4 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 213 µs | 198 µs | 93 % | behind |  |
| 5 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 4,975/s | 5,261/s | 95 % | behind | server CPU 201 vs 190 µs/handshake: of the 10.9 µs gap, 15.3 µs is primitive crypto (largest: P-256 ECDH shared, +11.7 µs), NURL's protocol / runtime / I/O is 4.45 µs CHEAPER than Rust's |
| 6 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 99,058/s | 102,828/s | 96 % | parity | not TLS: the HTTP/1.1 server itself |
| 7 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 5,343/s | 5,522/s | 97 % | parity | server CPU 187 vs 181 µs/handshake: of the 6.18 µs gap, 6.65 µs is primitive crypto (largest: ML-KEM-768 encaps, +2.83 µs), NURL's protocol / runtime / I/O is 0.47 µs CHEAPER than Rust's |
| 8 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,059 MB/s | 1,082 MB/s | 98 % | parity | server CPU 919 vs 900 ns/KB; the AEAD alone is 454 vs 388 ns/KB |
| 9 | record layer | Keep-alive 1 KB over TLS — req/s | 89,805/s | 90,192/s | 100 % | parity | TLS adds 1.01 µs CPU per request on NURL, 1.34 µs on Rust (TLS minus plaintext) |
| 10 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 6,254/s | 6,277/s | 100 % | parity | server CPU 160 vs 159 µs/handshake: of the 0.69 µs gap, 3.82 µs is primitive crypto (largest: X25519 shared, +2.69 µs), NURL's protocol / runtime / I/O is 3.13 µs CHEAPER than Rust's |
| 11 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 326 µs | 328 µs | 101 % | parity |  |
| 12 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 366 µs | 369 µs | 101 % | parity |  |
| 13 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,995 MB/s | 1,943 MB/s | 103 % | parity | server CPU 493 vs 504 ns/KB; the AEAD alone is 89.9 vs 88.8 ns/KB |
| 14 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 7,629/s | 7,055/s | 108 % | ahead | server CPU/handshake 131 vs 141 µs |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 2,038/s | 1,624/s | 125 % | ahead | p50 487 vs 612 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,970/s | 1,469/s | 134 % | ahead | p50 503 vs 673 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 28,222/s | 20,977/s | 135 % | ahead |  |
| 18 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 1,910 MB/s | 1,214 MB/s | 157 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 6,254 | 100 % | 160 | 54.7 | 105 | 5,430 / 6,687 | 298 | — |
| Full · ECDSA P-256 · X25519 | RUST | 6,277 | 100 % | 159 | 50.9 | 108 | 5,887 / 7,899 | 271 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 7,629 | 100 % | 131 | 37.8 | 92.9 | 4,360 / 5,302 | 213 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 7,055 | 100 % | 141 | 35.7 | 106 | 5,468 / 7,337 | 198 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 4,975 | 100 % | 201 | 87.2 | 113 | 6,846 / 8,827 | 326 | — |
| Full · ECDSA P-256 · P-256 | RUST | 5,261 | 100 % | 190 | 71.9 | 118 | 7,058 / 9,193 | 328 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 5,343 | 100 % | 187 | 69.8 | 117 | 6,381 / 7,826 | 366 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 5,522 | 100 % | 181 | 63.2 | 118 | 7,052 / 9,557 | 369 | — |
| Full · RSA-2048 · X25519 | NURL | 2,186 | 100 % | 456 | 342 | 114 | 15,304 / 20,656 | 545 | — |
| Full · RSA-2048 · X25519 | RUST | 2,571 | 100 % | 388 | 277 | 112 | 12,134 / 20,321 | 460 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 89,805 | 100 % | 11.1 | 708 / 835 | 1.01 |
| NURL | plaintext | 99,058 | 100 % | 10.1 | 651 / 701 |  |
| RUST | TLS | 90,192 | 100 % | 11.1 | 714 / 814 | 1.34 |
| RUST | plaintext | 102,828 | 100 % | 9.72 | 632 / 699 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,995 | 96 % | 493 | 89.9 | — |
| NURL | chacha | 1,059 | 95 % | 919 | 454 | — |
| NURL | plain | 4,786 | 95 % | 203 | n/a | — |
| NURL | aes128+ktls | 1,308 | 68 % | 535 | 89.9 | yes |
| RUST | aes128 | 1,943 | 96 % | 504 | 88.8 | — |
| RUST | chacha | 1,082 | 95 % | 900 | 388 | — |
| RUST | plain | 4,801 | 94 % | 200 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,970 | 0.03 | 503 / 566 | 0 |
| full:/ | reqwest | 1,469 | 0.02 | 673 / 828 | 0 |
| resume:/ | http-client | 2,038 | 0.03 | 487 / 540 | 0 |
| resume:/ | reqwest | 1,624 | 0.02 | 612 / 653 | 0 |
| ka:/1k | http-client | 28,222 | 28.9 | 34.0 / 50.0 | 0 |
| ka:/1k | reqwest | 20,977 | 21.5 | 46.0 / 65.0 | 0 |
| ka:/1m | http-client | 1,821 | 1,910 | 549 / 584 | 0 |
| ka:/1m | reqwest | 1,157 | 1,214 | 744 / 1,154 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 9.09 | 7.67 | 84 % |
| X25519 shared | `adx` | 26.8 | 24.2 | 90 % |
| P-256 ECDH keygen | `adx` | 12.8 | 8.89 | 69 % |
| P-256 ECDH shared | `adx` | 55.6 | 43.9 | 79 % |
| ML-KEM-768 encaps | `avx2` | 15.1 | 12.3 | 81 % |
| ECDSA P-256 sign | `adx` | 16.9 | 15.2 | 90 % |
| ECDSA P-256 verify | `adx` | 58.0 | 49.8 | 86 % |
| RSA-2048 PSS sign | `ifma` | 304 | 241 | 79 % |
| HKDF-Expand-Label | `sha-ni` | 0.12 | 0.24 | 206 % |
| SHA-256 16 KB | `sha-ni` | 9.11 | 9.05 | 99 % |
| AES-128-GCM seal 16 KB | `vaes512` | 1.44 | 1.42 | 99 % |
| ChaCha20-Poly1305 seal 16 KB | `avx2` | 7.27 | 6.20 | 85 % |

## Environment

| Item | Value |
|---|---|
| CPU family | `amd-avx512ifma-vaes-sha-adx` (vendor and flags; see bench/tls_bench/README.md) |
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | `AMD EPYC 9V74 80-Core Processor` |
| CPU vendor | `AuthenticAMD` |
| CPU flags (the crypto-relevant ones present) | `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq gfni avx512f avx512vl avx512bw avx512ifma avx512vbmi` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `d390e6e3c5ece34fad15a0732d39ad5e18a8e3db` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41186587658 |
| NURL | `v0.82.0-12-gd390e6e3` |
| NURL_CPU_* masking | `none` |
| OPENSSL_ia32cap (aws-lc's CPUID mask) | `unset` |
| Rust | `rustc 1.99.1 (58cf8f9c3 2026-10-13)` |
| Cell durations (s) | `hs=15 lat=5 ka=10 client=6 prim_runs=3` |
| rustls | `0.23.46` |
| aws-lc-rs | `1.18.2` |
| hyper | `1.12.0` |
| tokio | `1.54.1` |
| reqwest | `0.12.28` |
| NURL CPU probes | `v3=1 aes=1 vaes=1 vaes512=1 sha=1 adx=1 ifma=1` |

### Reading these numbers

- **Read pairs, not cells.** Both servers ran on the same cores in the same run; a shared CI VM moves absolute numbers between runs by more than it moves the ratio.
- **A ratio belongs to its CPU family.** aws-lc and NURL each pick kernels by CPUID, so the same code can lead on one family and trail on another. Compare this report only with an earlier one of the same family; the index sets the families side by side.
- **CPU per operation is the absolute number.** Rates depend on how many cores the server had; server CPU per handshake / per request / per KB does not, and it is what the crypto budget is subtracted from.
- **The crypto budget is a floor, not a model.** It counts each primitive once at its single-core, warm-cache cost. *Rest* therefore also holds cache misses the microbenchmark does not see — a large *rest* with a small primitive gap points at the protocol code, the allocator or the I/O path.
- **The client rows include the library.** http-client and reqwest are measured as an application calls them (pooling, header handling, response assembly), not as bare TLS.
