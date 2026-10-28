# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-28T03:57:46Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,747/s | 5,154/s | 73 % | **gap** | server CPU 266 vs 194 µs/handshake: of the 72.7 µs gap, 81.1 µs is primitive crypto (largest: P-256 ECDH shared, +55.7 µs), NURL's protocol / runtime / I/O is 8.39 µs CHEAPER than Rust's |
| 2 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 320 µs | 268 µs | 84 % | behind |  |
| 3 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,125/s | 2,529/s | 84 % | behind | server CPU 470 vs 395 µs/handshake: of the 75.0 µs gap, 76.7 µs is primitive crypto (largest: RSA-2048 PSS sign, +61.2 µs), NURL's protocol / runtime / I/O is 1.64 µs CHEAPER than Rust's |
| 4 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 4,519/s | 5,368/s | 84 % | behind | server CPU 221 vs 186 µs/handshake: of the 35.0 µs gap, 33.2 µs is primitive crypto (largest: ECDSA P-256 sign, +15.1 µs), 1.71 µs is protocol / runtime / I/O |
| 5 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 5,272/s | 6,227/s | 85 % | behind | server CPU 189 vs 160 µs/handshake: of the 29.0 µs gap, 30.6 µs is primitive crypto (largest: ECDSA P-256 sign, +15.1 µs), NURL's protocol / runtime / I/O is 1.56 µs CHEAPER than Rust's |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 393 µs | 334 µs | 85 % | behind |  |
| 7 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 564 µs | 491 µs | 87 % | behind |  |
| 8 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 405 µs | 356 µs | 88 % | behind |  |
| 9 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 227 µs | 204 µs | 90 % | behind |  |
| 10 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 99,137/s | 103,633/s | 96 % | parity | not TLS: the HTTP/1.1 server itself |
| 11 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,918 MB/s | 1,969 MB/s | 97 % | parity | server CPU 510 vs 497 ns/KB; the AEAD alone is 118 vs 89.6 ns/KB |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 6,833/s | 6,968/s | 98 % | parity | server CPU 146 vs 143 µs/handshake: of the 2.93 µs gap, 15.5 µs is primitive crypto (largest: X25519 shared, +12.7 µs), NURL's protocol / runtime / I/O is 12.6 µs CHEAPER than Rust's |
| 13 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,114 MB/s | 1,125 MB/s | 99 % | parity | server CPU 872 vs 865 ns/KB; the AEAD alone is 450 vs 391 ns/KB |
| 14 | record layer | Keep-alive 1 KB over TLS — req/s | 90,100/s | 88,654/s | 102 % | parity | TLS adds 0.98 µs CPU per request on NURL, 1.59 µs on Rust (TLS minus plaintext) |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,917/s | 1,592/s | 120 % | ahead | p50 519 vs 624 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,857/s | 1,441/s | 129 % | ahead | p50 531 vs 688 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 27,823/s | 20,112/s | 138 % | ahead |  |
| 18 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 1,979 MB/s | 1,173 MB/s | 169 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 5,272 | 100 % | 189 | 82.0 | 107 | 6,404 / 8,238 | 320 | — |
| Full · ECDSA P-256 · X25519 | RUST | 6,227 | 100 % | 160 | 51.4 | 109 | 5,938 / 7,719 | 268 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 6,833 | 100 % | 146 | 51.6 | 94.5 | 4,905 / 5,820 | 227 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 6,968 | 100 % | 143 | 36.1 | 107 | 5,548 / 7,487 | 204 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,747 | 100 % | 266 | 154 | 113 | 8,945 / 12,144 | 405 | — |
| Full · ECDSA P-256 · P-256 | RUST | 5,154 | 100 % | 194 | 72.6 | 121 | 6,279 / 8,891 | 356 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 4,519 | 100 % | 221 | 97.8 | 123 | 7,465 / 9,548 | 393 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 5,368 | 100 % | 186 | 64.6 | 121 | 6,088 / 8,812 | 334 | — |
| Full · RSA-2048 · X25519 | NURL | 2,125 | 100 % | 470 | 355 | 115 | 15,671 / 21,352 | 564 | — |
| Full · RSA-2048 · X25519 | RUST | 2,529 | 100 % | 395 | 278 | 117 | 14,792 / 19,214 | 491 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 90,100 | 100 % | 11.1 | 704 / 800 | 0.98 |
| NURL | plaintext | 99,137 | 100 % | 10.1 | 652 / 705 |  |
| RUST | TLS | 88,654 | 100 % | 11.2 | 724 / 837 | 1.59 |
| RUST | plaintext | 103,633 | 100 % | 9.64 | 627 / 695 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,918 | 96 % | 510 | 118 | — |
| NURL | chacha | 1,114 | 95 % | 872 | 450 | — |
| NURL | plain | 4,882 | 94 % | 198 | n/a | — |
| NURL | aes128+ktls | 1,343 | 67 % | 512 | 118 | yes |
| RUST | aes128 | 1,969 | 96 % | 497 | 89.6 | — |
| RUST | chacha | 1,125 | 95 % | 865 | 391 | — |
| RUST | plain | 4,884 | 94 % | 197 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,857 | 0.03 | 531 / 799 | 0 |
| full:/ | reqwest | 1,441 | 0.02 | 688 / 733 | 0 |
| resume:/ | http-client | 1,917 | 0.03 | 519 / 570 | 0 |
| resume:/ | reqwest | 1,592 | 0.02 | 624 / 671 | 0 |
| ka:/1k | http-client | 27,823 | 28.5 | 35.0 / 50.0 | 0 |
| ka:/1k | reqwest | 20,112 | 20.6 | 48.0 / 67.0 | 0 |
| ka:/1m | http-client | 1,887 | 1,979 | 522 / 819 | 0 |
| ka:/1m | reqwest | 1,118 | 1,173 | 884 / 1,014 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 12.8 | 7.67 | 60 % |
| X25519 shared | 37.0 | 24.2 | 66 % |
| P-256 ECDH keygen | 21.6 | 8.90 | 41 % |
| P-256 ECDH shared | 99.8 | 44.2 | 44 % |
| ML-KEM-768 encaps | 15.8 | 13.2 | 83 % |
| ECDSA P-256 sign | 30.4 | 15.3 | 50 % |
| ECDSA P-256 verify | 119 | 50.0 | 42 % |
| RSA-2048 PSS sign | 303 | 242 | 80 % |
| HKDF-Expand-Label | 0.12 | 0.26 | 228 % |
| SHA-256 16 KB | 9.12 | 9.05 | 99 % |
| AES-128-GCM seal 16 KB | 1.90 | 1.43 | 76 % |
| ChaCha20-Poly1305 seal 16 KB | 7.21 | 6.26 | 87 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | `AMD EPYC 9V74 80-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `25c94231b207023db895528e39e271d2b767b125` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40629250962 |
| NURL | `v0.79.1-10-g25c94231` |
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
