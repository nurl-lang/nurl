# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `amd-avx512ifma-vaes-sha-adx`

Generated `2026-11-25T09:53:30Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `AMD EPYC 9V45 96-Core Processor`, commit `c46fd726f851`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/45588946841). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `amd-avx512ifma-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 224 µs | 183 µs | 82 % | behind |  |
| 2 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,822/s | 3,251/s | 87 % | behind | server CPU 354 vs 307 µs/handshake: of the 46.7 µs gap, 47.7 µs is primitive crypto (largest: RSA-2048 PSS sign, +45.3 µs), NURL's protocol / runtime / I/O is 1.04 µs CHEAPER than Rust's |
| 3 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 2,850 MB/s | 3,168 MB/s | 90 % | behind | server CPU 342 vs 306 ns/KB; the AEAD alone is 52.2 vs 42.4 ns/KB |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 250 µs | 229 µs | 92 % | behind |  |
| 5 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 412 µs | 387 µs | 94 % | behind |  |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 7,275/s | 7,621/s | 95 % | parity | server CPU 137 vs 131 µs/handshake: of the 6.32 µs gap, 2.37 µs is primitive crypto (largest: X25519 shared, +3.00 µs), 3.95 µs is protocol / runtime / I/O |
| 7 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 7,195/s | 7,505/s | 96 % | parity | server CPU 139 vs 133 µs/handshake: of the 5.73 µs gap, 6.27 µs is primitive crypto (largest: P-256 ECDH shared, +6.32 µs), NURL's protocol / runtime / I/O is 0.54 µs CHEAPER than Rust's |
| 8 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 114,342/s | 118,591/s | 96 % | parity | not TLS: the HTTP/1.1 server itself |
| 9 | record layer | Keep-alive 1 KB over TLS — req/s | 109,118/s | 109,467/s | 100 % | parity | TLS adds 0.41 µs CPU per request on NURL, 0.68 µs on Rust (TLS minus plaintext) |
| 10 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 8,914/s | 8,807/s | 101 % | parity | server CPU/handshake 112 vs 113 µs |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 133 µs | 135 µs | 102 % | parity |  |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 10,024/s | 9,656/s | 104 % | parity | server CPU/handshake 99.6 vs 103 µs |
| 13 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 236 µs | 248 µs | 105 % | ahead |  |
| 14 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,547 MB/s | 1,414 MB/s | 109 % | ahead | server CPU 492 vs 688 ns/KB; the AEAD alone is 216 vs 365 ns/KB |
| 15 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 33,930/s | 29,334/s | 116 % | ahead |  |
| 16 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 2,290/s | 1,936/s | 118 % | ahead | p50 429 vs 510 µs per request |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 2,220/s | 1,742/s | 127 % | ahead | p50 439 vs 568 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 2,550 MB/s | 1,777 MB/s | 144 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 8,914 | 100 % | 112 | 37.7 | 74.3 | 3,810 / 4,537 | 224 | — |
| Full · ECDSA P-256 · X25519 | RUST | 8,807 | 100 % | 113 | 35.4 | 77.9 | 4,343 / 5,810 | 183 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 10,024 | 100 % | 99.6 | 26.7 | 73.0 | 3,316 / 3,885 | 133 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 9,656 | 100 % | 103 | 24.2 | 79.2 | 3,764 / 5,147 | 135 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 7,195 | 100 % | 139 | 56.2 | 82.5 | 4,751 / 5,789 | 250 | — |
| Full · ECDSA P-256 · P-256 | RUST | 7,505 | 100 % | 133 | 49.9 | 83.1 | 4,367 / 6,392 | 229 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 7,275 | 100 % | 137 | 48.3 | 89.0 | 4,689 / 5,718 | 236 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 7,621 | 100 % | 131 | 45.9 | 85.0 | 4,744 / 6,389 | 248 | — |
| Full · RSA-2048 · X25519 | NURL | 2,822 | 100 % | 354 | 278 | 75.4 | 11,818 / 16,216 | 412 | — |
| Full · RSA-2048 · X25519 | RUST | 3,251 | 100 % | 307 | 231 | 76.4 | 9,648 / 16,865 | 387 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 109,118 | 100 % | 9.15 | 580 / 731 | 0.41 |
| NURL | plaintext | 114,342 | 100 % | 8.74 | 560 / 608 |  |
| RUST | TLS | 109,467 | 100 % | 9.11 | 587 / 654 | 0.68 |
| RUST | plaintext | 118,591 | 100 % | 8.42 | 547 / 652 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 2,850 | 95 % | 342 | 52.2 | — |
| NURL | chacha | 1,547 | 74 % | 492 | 216 | — |
| NURL | plain | 6,651 | 93 % | 144 | n/a | — |
| NURL | aes128+ktls | 1,367 | 89 % | 670 | 52.2 | yes |
| RUST | aes128 | 3,168 | 95 % | 306 | 42.4 | — |
| RUST | chacha | 1,414 | 95 % | 688 | 365 | — |
| RUST | plain | 6,077 | 92 % | 155 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 2,220 | 0.03 | 439 / 782 | 0 |
| full:/ | reqwest | 1,742 | 0.02 | 568 / 627 | 0 |
| resume:/ | http-client | 2,290 | 0.03 | 429 / 510 | 0 |
| resume:/ | reqwest | 1,936 | 0.03 | 510 / 574 | 0 |
| ka:/1k | http-client | 33,930 | 34.7 | 28.0 / 40.0 | 0 |
| ka:/1k | reqwest | 29,334 | 30.0 | 33.0 / 46.0 | 0 |
| ka:/1m | http-client | 2,432 | 2,550 | 411 / 463 | 0 |
| ka:/1m | reqwest | 1,694 | 1,777 | 497 / 924 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 5.96 | 5.05 | 85 % |
| X25519 shared | `adx` | 19.1 | 16.1 | 84 % |
| P-256 ECDH keygen | `adx` | 8.05 | 6.44 | 80 % |
| P-256 ECDH shared | `adx` | 35.5 | 29.2 | 82 % |
| ML-KEM-768 encaps | `avx2` | 10.6 | 10.5 | 99 % |
| ECDSA P-256 sign | `adx` | 11.0 | 11.2 | 102 % |
| ECDSA P-256 verify | `adx` | 37.7 | 33.9 | 90 % |
| RSA-2048 PSS sign | `ifma` | 252 | 207 | 82 % |
| HKDF-Expand-Label | `sha-ni` | 0.10 | 0.19 | 191 % |
| SHA-256 16 KB | `sha-ni` | 7.84 | 7.91 | 101 % |
| AES-128-GCM seal 16 KB | `vaes512` | 0.83 | 0.68 | 81 % |
| ChaCha20-Poly1305 seal 16 KB | `avx512` | 3.46 | 5.84 | 169 % |

## Environment

| Item | Value |
|---|---|
| CPU family | `amd-avx512ifma-vaes-sha-adx` (vendor and flags; see bench/tls_bench/README.md) |
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1020-azure x86_64` |
| CPU | `AMD EPYC 9V45 96-Core Processor` |
| CPU vendor | `AuthenticAMD` |
| CPU flags (the crypto-relevant ones present) | `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq gfni avx512f avx512vl avx512bw avx512ifma avx512vbmi` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `c46fd726f851b3938d5fbdea2c3dc3edabd20edf` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/45588946841 |
| NURL | `v0.94.0-88-gc46fd726f` |
| NURL_CPU_* masking | `none` |
| OPENSSL_ia32cap (aws-lc's CPUID mask) | `unset` |
| Rust | `rustc 1.100.0 (0ef1bc386 2026-11-09)` |
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
