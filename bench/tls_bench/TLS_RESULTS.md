# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-26T15:39:42Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 4,947/s | 7,156/s | 69 % | **gap** | server CPU 202 vs 139 µs/handshake: of the 62.4 µs gap, 58.6 µs is primitive crypto (largest: P-256 ECDH shared, +41.1 µs), 3.81 µs is protocol / runtime / I/O |
| 2 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,096 MB/s | 1,376 MB/s | 80 % | behind | server CPU 885 vs 691 ns/KB; the AEAD alone is 464 vs 378 ns/KB |
| 3 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 483 µs | 392 µs | 81 % | behind |  |
| 4 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,588/s | 3,115/s | 83 % | behind | server CPU 386 vs 321 µs/handshake: of the 65.0 µs gap, 62.0 µs is primitive crypto (largest: RSA-2048 PSS sign, +50.4 µs), 3.03 µs is protocol / runtime / I/O |
| 5 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 7,026/s | 8,264/s | 85 % | behind | server CPU 142 vs 121 µs/handshake: of the 21.3 µs gap, 22.3 µs is primitive crypto (largest: ECDSA P-256 sign, +10.7 µs), NURL's protocol / runtime / I/O is 1.03 µs CHEAPER than Rust's |
| 6 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 245 µs | 209 µs | 85 % | behind |  |
| 7 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 6,091/s | 7,080/s | 86 % | behind | server CPU 164 vs 141 µs/handshake: of the 22.9 µs gap, 22.6 µs is primitive crypto (largest: ECDSA P-256 sign, +10.7 µs), 0.29 µs is protocol / runtime / I/O |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 307 µs | 271 µs | 88 % | behind |  |
| 9 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 301 µs | 267 µs | 89 % | behind |  |
| 10 | record layer | Keep-alive 1 KB over TLS — req/s | 87,958/s | 98,967/s | 89 % | behind | TLS adds 2.00 µs CPU per request on NURL, -0.34 µs on Rust (TLS minus plaintext) |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 8,883/s | 9,249/s | 96 % | parity | server CPU 112 vs 108 µs/handshake: of the 4.44 µs gap, 11.6 µs is primitive crypto (largest: X25519 shared, +9.32 µs), NURL's protocol / runtime / I/O is 7.12 µs CHEAPER than Rust's |
| 12 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 2,874 MB/s | 2,874 MB/s | 100 % | parity | server CPU 334 vs 285 ns/KB; the AEAD alone is 53.8 vs 43.9 ns/KB |
| 13 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 167 µs | 176 µs | 105 % | ahead |  |
| 14 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 106,938/s | 96,056/s | 111 % | ahead | not TLS: the HTTP/1.1 server itself |
| 15 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 30,093/s | 26,355/s | 114 % | ahead |  |
| 16 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 2,252/s | 1,915/s | 118 % | ahead | p50 438 vs 515 µs per request |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 2,212/s | 1,770/s | 125 % | ahead | p50 444 vs 558 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 2,699 MB/s | 1,699 MB/s | 159 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 7,026 | 100 % | 142 | 59.2 | 82.8 | 4,153 / 6,966 | 245 | — |
| Full · ECDSA P-256 · X25519 | RUST | 8,264 | 100 % | 121 | 36.9 | 83.9 | 4,480 / 5,887 | 209 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 8,883 | 100 % | 112 | 36.9 | 75.5 | 3,085 / 5,142 | 167 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 9,249 | 100 % | 108 | 25.3 | 82.6 | 3,560 / 5,128 | 176 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 4,947 | 100 % | 202 | 110 | 91.6 | 2,882 / 11,719 | 301 | — |
| Full · ECDSA P-256 · P-256 | RUST | 7,156 | 100 % | 139 | 51.7 | 87.8 | 4,541 / 6,496 | 267 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 6,091 | 100 % | 164 | 72.0 | 91.9 | 4,684 / 9,028 | 307 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 7,080 | 100 % | 141 | 49.4 | 91.6 | 4,619 / 6,548 | 271 | — |
| Full · RSA-2048 · X25519 | NURL | 2,588 | 100 % | 386 | 301 | 85.0 | 12,020 / 22,435 | 483 | — |
| Full · RSA-2048 · X25519 | RUST | 3,115 | 100 % | 321 | 239 | 81.9 | 9,951 / 17,368 | 392 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 87,958 | 100 % | 11.3 | 769 / 896 | 2.00 |
| NURL | plaintext | 106,938 | 100 % | 9.34 | 592 / 806 |  |
| RUST | TLS | 98,967 | 100 % | 10.1 | 647 / 783 | -0.34 |
| RUST | plaintext | 96,056 | 100 % | 10.4 | 674 / 738 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 2,874 | 94 % | 334 | 53.8 | — |
| NURL | chacha | 1,096 | 95 % | 885 | 464 | — |
| NURL | plain | 5,294 | 94 % | 182 | n/a | — |
| NURL | aes128+ktls | 1,340 | 95 % | 724 | 53.8 | yes |
| RUST | aes128 | 2,874 | 80 % | 285 | 43.9 | — |
| RUST | chacha | 1,376 | 93 % | 691 | 378 | — |
| RUST | plain | 5,808 | 91 % | 161 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 2,212 | 0.03 | 444 / 604 | 0 |
| full:/ | reqwest | 1,770 | 0.02 | 558 / 619 | 0 |
| resume:/ | http-client | 2,252 | 0.03 | 438 / 581 | 0 |
| resume:/ | reqwest | 1,915 | 0.03 | 515 / 592 | 0 |
| ka:/1k | http-client | 30,093 | 30.8 | 32.0 / 42.0 | 0 |
| ka:/1k | reqwest | 26,355 | 27.0 | 37.0 / 48.0 | 0 |
| ka:/1m | http-client | 2,574 | 2,699 | 376 / 471 | 0 |
| ka:/1m | reqwest | 1,620 | 1,699 | 500 / 1,029 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 9.28 | 5.09 | 55 % |
| X25519 shared | 26.0 | 16.7 | 64 % |
| P-256 ECDH keygen | 15.3 | 6.54 | 43 % |
| P-256 ECDH shared | 71.1 | 30.0 | 42 % |
| ML-KEM-768 encaps | 12.8 | 12.5 | 98 % |
| ECDSA P-256 sign | 22.3 | 11.5 | 52 % |
| ECDSA P-256 verify | 84.4 | 34.9 | 41 % |
| RSA-2048 PSS sign | 264 | 213 | 81 % |
| HKDF-Expand-Label | 0.10 | 0.22 | 220 % |
| SHA-256 16 KB | 8.07 | 8.02 | 99 % |
| AES-128-GCM seal 16 KB | 0.86 | 0.70 | 82 % |
| ChaCha20-Poly1305 seal 16 KB | 7.43 | 6.04 | 81 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 9V45 96-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `dac8d120fe107d84d086427b9a9e21b3b3a09bb1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40350850900 |
| NURL | `v0.78.0-27-gdac8d120` |
| Rust | `rustc 1.99.1 (58cf8f9c3 2026-10-13)` |
| Cell durations (s) | `hs=15 lat=5 ka=10 client=6 prim_runs=3` |
| rustls | `0.23.46` |
| aws-lc-rs | `1.18.2` |
| hyper | `1.12.0` |
| tokio | `1.54.1` |
| reqwest | `0.12.28` |

### Reading these numbers

- **Read pairs, not cells.** Both servers ran on the same cores in the same run; a shared CI VM moves absolute numbers between runs by more than it moves the ratio.
- **CPU per operation is the absolute number.** Rates depend on how many cores the server had; server CPU per handshake / per request / per KB does not, and it is what the crypto budget is subtracted from.
- **The crypto budget is a floor, not a model.** It counts each primitive once at its single-core, warm-cache cost. *Rest* therefore also holds cache misses the microbenchmark does not see — a large *rest* with a small primitive gap points at the protocol code, the allocator or the I/O path.
- **The client rows include the library.** http-client and reqwest are measured as an application calls them (pooling, header handling, response assembly), not as bare TLS.
