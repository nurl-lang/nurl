# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `amd-avx512ifma-vaes-sha-adx`

Generated `2026-11-06T17:25:21Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `AMD EPYC 9V74 80-Core Processor`, commit `a3be3e7c7302`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/42260807419). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `amd-avx512ifma-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,190/s | 2,541/s | 86 % | behind | server CPU 456 vs 393 µs/handshake: of the 62.9 µs gap, 65.4 µs is primitive crypto (largest: RSA-2048 PSS sign, +65.1 µs), NURL's protocol / runtime / I/O is 2.52 µs CHEAPER than Rust's |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 534 µs | 468 µs | 88 % | behind |  |
| 3 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 98,292/s | 101,051/s | 97 % | parity | not TLS: the HTTP/1.1 server itself |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 5,236/s | 5,222/s | 100 % | parity | server CPU/handshake 191 vs 191 µs |
| 5 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 2,013 MB/s | 2,005 MB/s | 100 % | parity | server CPU 476 vs 485 ns/KB; the AEAD alone is 89.6 vs 88.8 ns/KB |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 5,442/s | 5,389/s | 101 % | parity | server CPU/handshake 184 vs 185 µs |
| 7 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 349 µs | 357 µs | 102 % | parity |  |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 348 µs | 356 µs | 102 % | parity |  |
| 9 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 6,376/s | 6,229/s | 102 % | parity | server CPU/handshake 157 vs 160 µs |
| 10 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 294 µs | 301 µs | 102 % | parity |  |
| 11 | record layer | Keep-alive 1 KB over TLS — req/s | 90,188/s | 87,809/s | 103 % | parity | TLS adds 0.88 µs CPU per request on NURL, 1.46 µs on Rust (TLS minus plaintext) |
| 12 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,110 MB/s | 1,040 MB/s | 107 % | ahead | server CPU 719 vs 924 ns/KB; the AEAD alone is 343 vs 387 ns/KB |
| 13 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 217 µs | 235 µs | 108 % | ahead |  |
| 14 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 7,650/s | 6,945/s | 110 % | ahead | server CPU/handshake 130 vs 144 µs |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 2,018/s | 1,614/s | 125 % | ahead | p50 493 vs 615 µs per request |
| 16 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 27,653/s | 20,528/s | 135 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,973/s | 1,458/s | 135 % | ahead | p50 505 vs 679 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 1,878 MB/s | 1,377 MB/s | 136 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 6,376 | 100 % | 157 | 52.2 | 104 | 5,337 / 6,556 | 294 | — |
| Full · ECDSA P-256 · X25519 | RUST | 6,229 | 100 % | 160 | 51.0 | 109 | 5,938 / 7,796 | 301 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 7,650 | 100 % | 130 | 36.1 | 94.3 | 4,342 / 5,145 | 217 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 6,945 | 100 % | 144 | 35.7 | 108 | 4,611 / 6,016 | 235 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 5,236 | 100 % | 191 | 80.4 | 110 | 6,516 / 8,104 | 349 | — |
| Full · ECDSA P-256 · P-256 | RUST | 5,222 | 100 % | 191 | 71.9 | 119 | 6,200 / 8,739 | 357 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 5,442 | 100 % | 184 | 66.7 | 117 | 6,247 / 7,666 | 348 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 5,389 | 100 % | 185 | 63.2 | 122 | 6,012 / 8,395 | 356 | — |
| Full · RSA-2048 · X25519 | NURL | 2,190 | 100 % | 456 | 342 | 113 | 15,184 / 20,786 | 534 | — |
| Full · RSA-2048 · X25519 | RUST | 2,541 | 100 % | 393 | 277 | 116 | 12,156 / 20,555 | 468 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 90,188 | 100 % | 11.1 | 707 / 783 | 0.88 |
| NURL | plaintext | 98,292 | 100 % | 10.2 | 656 / 707 |  |
| RUST | TLS | 87,809 | 100 % | 11.3 | 730 / 905 | 1.46 |
| RUST | plaintext | 101,051 | 100 % | 9.89 | 645 / 707 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 2,013 | 94 % | 476 | 89.6 | — |
| NURL | chacha | 1,110 | 78 % | 719 | 343 | — |
| NURL | plain | 4,648 | 94 % | 207 | n/a | — |
| NURL | aes128+ktls | 1,376 | 75 % | 560 | 89.6 | yes |
| RUST | aes128 | 2,005 | 95 % | 485 | 88.8 | — |
| RUST | chacha | 1,040 | 94 % | 924 | 387 | — |
| RUST | plain | 4,713 | 93 % | 201 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,973 | 0.03 | 505 / 553 | 0 |
| full:/ | reqwest | 1,458 | 0.02 | 679 / 790 | 0 |
| resume:/ | http-client | 2,018 | 0.03 | 493 / 542 | 0 |
| resume:/ | reqwest | 1,614 | 0.02 | 615 / 656 | 0 |
| ka:/1k | http-client | 27,653 | 28.3 | 35.0 / 52.0 | 0 |
| ka:/1k | reqwest | 20,528 | 21.0 | 47.0 / 67.0 | 0 |
| ka:/1m | http-client | 1,791 | 1,878 | 557 / 613 | 0 |
| ka:/1m | reqwest | 1,313 | 1,377 | 672 / 1,142 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 8.10 | 7.67 | 95 % |
| X25519 shared | `adx` | 26.2 | 24.2 | 93 % |
| P-256 ECDH keygen | `adx` | 11.9 | 8.84 | 74 % |
| P-256 ECDH shared | `adx` | 50.5 | 44.0 | 87 % |
| ML-KEM-768 encaps | `avx2` | 14.5 | 12.2 | 84 % |
| ECDSA P-256 sign | `adx` | 16.1 | 15.2 | 95 % |
| ECDSA P-256 verify | `adx` | 55.9 | 49.8 | 89 % |
| RSA-2048 PSS sign | `ifma` | 306 | 241 | 79 % |
| HKDF-Expand-Label | `sha-ni` | 0.12 | 0.24 | 207 % |
| SHA-256 16 KB | `sha-ni` | 9.11 | 9.06 | 99 % |
| AES-128-GCM seal 16 KB | `vaes512` | 1.43 | 1.42 | 99 % |
| ChaCha20-Poly1305 seal 16 KB | `avx512` | 5.49 | 6.20 | 113 % |

## Environment

| Item | Value |
|---|---|
| CPU family | `amd-avx512ifma-vaes-sha-adx` (vendor and flags; see bench/tls_bench/README.md) |
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | `AMD EPYC 9V74 80-Core Processor` |
| CPU vendor | `AuthenticAMD` |
| CPU flags (the crypto-relevant ones present) | `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq gfni avx512f avx512vl avx512bw avx512ifma avx512vbmi` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `a3be3e7c7302008216b075e2746e99a350284802` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42260807419 |
| NURL | `v0.89.0-4-ga3be3e7c` |
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
