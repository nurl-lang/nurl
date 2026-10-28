# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-28T02:38:32Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,675/s | 5,161/s | 71 % | **gap** | server CPU 272 vs 193 µs/handshake: of the 78.4 µs gap, 81.1 µs is primitive crypto (largest: P-256 ECDH shared, +55.7 µs), NURL's protocol / runtime / I/O is 2.76 µs CHEAPER than Rust's |
| 2 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,061/s | 2,542/s | 81 % | behind | server CPU 484 vs 393 µs/handshake: of the 91.8 µs gap, 76.6 µs is primitive crypto (largest: RSA-2048 PSS sign, +61.1 µs), 15.2 µs is protocol / runtime / I/O |
| 3 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 4,317/s | 5,298/s | 81 % | behind | server CPU 231 vs 188 µs/handshake: of the 42.9 µs gap, 33.2 µs is primitive crypto (largest: ECDSA P-256 sign, +15.1 µs), 9.67 µs is protocol / runtime / I/O |
| 4 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 5,231/s | 6,146/s | 85 % | behind | server CPU 191 vs 162 µs/handshake: of the 28.4 µs gap, 30.6 µs is primitive crypto (largest: ECDSA P-256 sign, +15.1 µs), NURL's protocol / runtime / I/O is 2.25 µs CHEAPER than Rust's |
| 5 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 395 µs | 338 µs | 86 % | behind |  |
| 6 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 417 µs | 357 µs | 86 % | behind |  |
| 7 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 549 µs | 473 µs | 86 % | behind |  |
| 8 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 323 µs | 280 µs | 87 % | behind |  |
| 9 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,038 MB/s | 1,105 MB/s | 94 % | behind | server CPU 805 vs 865 ns/KB; the AEAD alone is 455 vs 386 ns/KB |
| 10 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 6,484/s | 6,892/s | 94 % | behind | server CPU 154 vs 145 µs/handshake: of the 9.11 µs gap, 15.5 µs is primitive crypto (largest: X25519 shared, +12.8 µs), NURL's protocol / runtime / I/O is 6.42 µs CHEAPER than Rust's |
| 11 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 97,351/s | 98,790/s | 99 % | parity | not TLS: the HTTP/1.1 server itself |
| 12 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,998 MB/s | 2,016 MB/s | 99 % | parity | server CPU 470 vs 482 ns/KB; the AEAD alone is 118 vs 89.4 ns/KB |
| 13 | record layer | Keep-alive 1 KB over TLS — req/s | 87,674/s | 84,056/s | 104 % | parity | TLS adds 1.10 µs CPU per request on NURL, 1.75 µs on Rust (TLS minus plaintext) |
| 14 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 202 µs | 232 µs | 115 % | ahead |  |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,911/s | 1,598/s | 120 % | ahead | p50 519 vs 616 µs per request |
| 16 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 1,883 MB/s | 1,522 MB/s | 124 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,867/s | 1,440/s | 130 % | ahead | p50 531 vs 684 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 24,329/s | 18,559/s | 131 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 5,231 | 100 % | 191 | 81.9 | 109 | 6,461 / 8,281 | 323 | — |
| Full · ECDSA P-256 · X25519 | RUST | 6,146 | 100 % | 162 | 51.3 | 111 | 6,358 / 8,404 | 280 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 6,484 | 100 % | 154 | 51.6 | 102 | 5,144 / 6,345 | 202 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 6,892 | 100 % | 145 | 36.1 | 109 | 5,582 / 7,564 | 232 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,675 | 100 % | 272 | 154 | 118 | 9,081 / 12,280 | 417 | — |
| Full · ECDSA P-256 · P-256 | RUST | 5,161 | 100 % | 193 | 72.4 | 121 | 6,282 / 8,923 | 357 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 4,317 | 100 % | 231 | 97.7 | 133 | 7,789 / 10,180 | 395 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 5,298 | 100 % | 188 | 64.4 | 124 | 6,701 / 9,790 | 338 | — |
| Full · RSA-2048 · X25519 | NURL | 2,061 | 100 % | 484 | 354 | 130 | 16,259 / 21,865 | 549 | — |
| Full · RSA-2048 · X25519 | RUST | 2,542 | 100 % | 393 | 278 | 115 | 12,237 / 20,062 | 473 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 87,674 | 100 % | 11.4 | 729 / 792 | 1.10 |
| NURL | plaintext | 97,351 | 100 % | 10.3 | 660 / 722 |  |
| RUST | TLS | 84,056 | 100 % | 11.9 | 766 / 892 | 1.75 |
| RUST | plaintext | 98,790 | 100 % | 10.1 | 658 / 710 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,998 | 92 % | 470 | 118 | — |
| NURL | chacha | 1,038 | 82 % | 805 | 455 | — |
| NURL | plain | 4,877 | 94 % | 197 | n/a | — |
| NURL | aes128+ktls | 1,318 | 63 % | 489 | 118 | yes |
| RUST | aes128 | 2,016 | 95 % | 482 | 89.4 | — |
| RUST | chacha | 1,105 | 93 % | 865 | 386 | — |
| RUST | plain | 4,694 | 91 % | 199 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,867 | 0.03 | 531 / 632 | 0 |
| full:/ | reqwest | 1,440 | 0.02 | 684 / 776 | 0 |
| resume:/ | http-client | 1,911 | 0.03 | 519 / 613 | 0 |
| resume:/ | reqwest | 1,598 | 0.02 | 616 / 716 | 0 |
| ka:/1k | http-client | 24,329 | 24.9 | 40.0 / 54.0 | 0 |
| ka:/1k | reqwest | 18,559 | 19.0 | 52.0 / 69.0 | 0 |
| ka:/1m | http-client | 1,796 | 1,883 | 552 / 830 | 0 |
| ka:/1m | reqwest | 1,451 | 1,522 | 624 / 958 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 12.7 | 7.66 | 60 % |
| X25519 shared | 37.0 | 24.2 | 65 % |
| P-256 ECDH keygen | 21.6 | 8.86 | 41 % |
| P-256 ECDH shared | 99.8 | 44.1 | 44 % |
| ML-KEM-768 encaps | 15.8 | 13.2 | 83 % |
| ECDSA P-256 sign | 30.3 | 15.2 | 50 % |
| ECDSA P-256 verify | 121 | 50.0 | 41 % |
| RSA-2048 PSS sign | 303 | 242 | 80 % |
| HKDF-Expand-Label | 0.12 | 0.26 | 228 % |
| SHA-256 16 KB | 9.11 | 9.04 | 99 % |
| AES-128-GCM seal 16 KB | 1.90 | 1.43 | 75 % |
| ChaCha20-Poly1305 seal 16 KB | 7.28 | 6.18 | 85 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 9V74 80-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `8c17928f901cd70086613f6fb8de1385ff604854` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40621724074 |
| NURL | `v0.79.1-4-g8c17928f` |
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
