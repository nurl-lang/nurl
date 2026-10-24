# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-24T09:53:22Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 1,309/s | 3,215/s | 41 % | **gap** | server CPU 763 vs 311 µs/handshake: of the 453 µs gap, 415 µs is primitive crypto (largest: RSA-2048 PSS sign, +404 µs), 37.3 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 793 µs | 373 µs | 47 % | **gap** |  |
| 3 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 4,727/s | 7,537/s | 63 % | **gap** | server CPU 211 vs 133 µs/handshake: of the 78.8 µs gap, 70.0 µs is primitive crypto (largest: P-256 ECDH shared, +36.9 µs), 8.80 µs is protocol / runtime / I/O |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 301 µs | 221 µs | 73 % | **gap** |  |
| 5 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 162 µs | 128 µs | 79 % | behind |  |
| 6 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,116 MB/s | 1,387 MB/s | 80 % | behind | server CPU 881 vs 699 ns/KB; the AEAD alone is 436 vs 366 ns/KB |
| 7 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 6,962/s | 8,619/s | 81 % | behind | server CPU 143 vs 116 µs/handshake: of the 27.6 µs gap, 30.7 µs is primitive crypto (largest: ECDSA P-256 sign, +19.2 µs), NURL's protocol / runtime / I/O is 3.11 µs CHEAPER than Rust's |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 5,883/s | 7,188/s | 82 % | behind | server CPU 170 vs 139 µs/handshake: of the 30.8 µs gap, 31.0 µs is primitive crypto (largest: ECDSA P-256 sign, +19.2 µs), NURL's protocol / runtime / I/O is 0.16 µs CHEAPER than Rust's |
| 9 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 2,819 MB/s | 3,127 MB/s | 90 % | behind | server CPU 343 vs 311 ns/KB; the AEAD alone is 51.2 vs 42.6 ns/KB |
| 10 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 9,166/s | 9,638/s | 95 % | parity | server CPU 109 vs 104 µs/handshake: of the 5.26 µs gap, 11.4 µs is primitive crypto (largest: X25519 shared, +9.18 µs), NURL's protocol / runtime / I/O is 6.18 µs CHEAPER than Rust's |
| 11 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 118,918/s | 118,183/s | 101 % | parity | not TLS: the HTTP/1.1 server itself |
| 12 | record layer | Keep-alive 1 KB over TLS — req/s | 107,868/s | 107,190/s | 101 % | parity | TLS adds 0.84 µs CPU per request on NURL, 0.86 µs on Rust (TLS minus plaintext) |
| 13 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 208 µs | 216 µs | 104 % | parity |  |
| 14 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 269 µs | 282 µs | 105 % | parity |  |
| 15 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 2,749 MB/s | 2,505 MB/s | 110 % | ahead |  |
| 16 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 30,523/s | 26,923/s | 113 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 2,244/s | 1,941/s | 116 % | ahead | p50 442 vs 510 µs per request |
| 18 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 2,152/s | 1,738/s | 124 % | ahead | p50 457 vs 569 µs per request |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 6,962 | 100 % | 143 | 65.5 | 77.8 | 3,324 / 7,768 | 208 | — |
| Full · ECDSA P-256 · X25519 | RUST | 8,619 | 100 % | 116 | 34.8 | 81.0 | 3,779 / 5,403 | 216 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 9,166 | 100 % | 109 | 35.5 | 73.3 | 3,160 / 5,027 | 162 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 9,638 | 100 % | 104 | 24.1 | 79.5 | 3,375 / 5,164 | 128 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 4,727 | 100 % | 211 | 120 | 91.7 | 2,674 / 12,422 | 301 | — |
| Full · ECDSA P-256 · P-256 | RUST | 7,537 | 100 % | 133 | 49.6 | 82.9 | 5,163 / 6,901 | 221 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 5,883 | 100 % | 170 | 78.0 | 91.8 | 2,205 / 9,471 | 269 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 7,188 | 100 % | 139 | 47.0 | 91.9 | 4,737 / 6,665 | 282 | — |
| Full · RSA-2048 · X25519 | NURL | 1,309 | 100 % | 763 | 643 | 120 | 23,464 / 45,616 | 793 | — |
| Full · RSA-2048 · X25519 | RUST | 3,215 | 100 % | 311 | 228 | 82.8 | 9,670 / 17,842 | 373 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 107,868 | 100 % | 9.25 | 609 / 813 | 0.84 |
| NURL | plaintext | 118,918 | 100 % | 8.41 | 554 / 696 |  |
| RUST | TLS | 107,190 | 100 % | 9.31 | 603 / 685 | 0.86 |
| RUST | plaintext | 118,183 | 100 % | 8.45 | 546 / 687 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 2,819 | 94 % | 343 | 51.2 | — |
| NURL | chacha | 1,116 | 96 % | 881 | 436 | — |
| NURL | plain | 6,136 | 92 % | 154 | n/a | — |
| NURL | aes128+ktls | 1,567 | 70 % | 460 | 51.2 | yes |
| RUST | aes128 | 3,127 | 95 % | 311 | 42.6 | — |
| RUST | chacha | 1,387 | 95 % | 699 | 366 | — |
| RUST | plain | 6,101 | 91 % | 153 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 2,152 | 0.03 | 457 / 607 | 0 |
| full:/ | reqwest | 1,738 | 0.02 | 569 / 629 | 0 |
| resume:/ | http-client | 2,244 | 0.03 | 442 / 509 | 0 |
| resume:/ | reqwest | 1,941 | 0.03 | 510 / 571 | 0 |
| ka:/1k | http-client | 30,523 | 31.3 | 32.0 / 42.0 | 0 |
| ka:/1k | reqwest | 26,923 | 27.6 | 36.0 / 46.0 | 0 |
| ka:/1m | http-client | 2,622 | 2,749 | 376 / 443 | 0 |
| ka:/1m | reqwest | 2,389 | 2,505 | 411 / 534 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 8.95 | 4.81 | 54 % |
| X25519 shared | 25.0 | 15.8 | 63 % |
| P-256 ECDH keygen | 22.1 | 6.34 | 29 % |
| P-256 ECDH shared | 65.9 | 29.1 | 44 % |
| ML-KEM-768 encaps | 12.5 | 12.2 | 98 % |
| ECDSA P-256 sign | 30.0 | 10.8 | 36 % |
| ECDSA P-256 verify | 82.2 | 33.9 | 41 % |
| RSA-2048 PSS sign | 608 | 204 | 34 % |
| HKDF-Expand-Label | 0.10 | 0.22 | 217 % |
| SHA-256 16 KB | 7.69 | 7.75 | 101 % |
| AES-128-GCM seal 16 KB | 0.82 | 0.68 | 83 % |
| ChaCha20-Poly1305 seal 16 KB | 6.97 | 5.85 | 84 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 9V45 96-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `a02dbce43d58e6a56e96f1ddbdf5fe7654291c63` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40083497294 |
| NURL | `v0.77.2-38-ga02dbce4` |
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
