# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-24T04:52:01Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 645/s | 2,111/s | 31 % | **major gap** | server CPU 1,545 vs 472 µs/handshake: of the 1,073 µs gap, 1,030 µs is primitive crypto (largest: RSA-2048 PSS sign, +1,006 µs), 43.2 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,647 µs | 548 µs | 33 % | **major gap** |  |
| 3 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 2,946/s | 4,790/s | 61 % | **gap** | server CPU 339 vs 208 µs/handshake: of the 130 µs gap, 122 µs is primitive crypto (largest: P-256 ECDH shared, +64.6 µs), 8.23 µs is protocol / runtime / I/O |
| 4 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,530/s | 4,780/s | 74 % | **gap** | server CPU 283 vs 209 µs/handshake: of the 74.0 µs gap, 68.7 µs is primitive crypto (largest: ECDSA P-256 sign, +33.4 µs), 5.38 µs is protocol / runtime / I/O |
| 5 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,305/s | 5,485/s | 78 % | behind | server CPU 232 vs 182 µs/handshake: of the 50.0 µs gap, 56.5 µs is primitive crypto (largest: ECDSA P-256 sign, +33.4 µs), NURL's protocol / runtime / I/O is 6.55 µs CHEAPER than Rust's |
| 6 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 503 µs | 405 µs | 81 % | behind |  |
| 7 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 440 µs | 380 µs | 86 % | behind |  |
| 8 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 344 µs | 301 µs | 88 % | behind |  |
| 9 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 6,229/s | 6,437/s | 97 % | parity | server CPU 160 vs 155 µs/handshake: of the 5.07 µs gap, 23.2 µs is primitive crypto (largest: X25519 shared, +19.1 µs), NURL's protocol / runtime / I/O is 18.1 µs CHEAPER than Rust's |
| 10 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 112,862/s | 113,990/s | 99 % | parity | not TLS: the HTTP/1.1 server itself |
| 11 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 936 MB/s | 906 MB/s | 103 % | parity | server CPU 980 vs 1,077 ns/KB; the AEAD alone is 522 vs 494 ns/KB |
| 12 | record layer | Keep-alive 1 KB over TLS — req/s | 95,238/s | 88,540/s | 108 % | ahead | TLS adds 1.61 µs CPU per request on NURL, 2.50 µs on Rust (TLS minus plaintext) |
| 13 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 2,363 MB/s | 2,156 MB/s | 110 % | ahead | server CPU 407 vs 446 ns/KB; the AEAD alone is 89.6 vs 81.4 ns/KB |
| 14 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,724/s | 1,566/s | 110 % | ahead | p50 577 vs 632 µs per request |
| 15 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 222 µs | 256 µs | 115 % | ahead |  |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,623/s | 1,395/s | 116 % | ahead | p50 614 vs 709 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 1,783 MB/s | 1,372 MB/s | 130 % | ahead |  |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 23,939/s | 15,525/s | 154 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,305 | 100 % | 232 | 113 | 119 | 5,464 / 14,755 | 344 | — |
| Full · ECDSA P-256 · X25519 | RUST | 5,485 | 100 % | 182 | 56.6 | 125 | 6,519 / 8,868 | 301 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 6,229 | 100 % | 160 | 62.2 | 97.9 | 4,560 / 8,958 | 222 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 6,437 | 100 % | 155 | 39.1 | 116 | 5,957 / 8,535 | 256 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 2,946 | 100 % | 339 | 203 | 136 | 9,677 / 22,128 | 503 | — |
| Full · ECDSA P-256 · P-256 | RUST | 4,790 | 100 % | 208 | 80.6 | 128 | 8,065 / 10,537 | 405 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,530 | 100 % | 283 | 141 | 142 | 6,122 / 18,635 | 440 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,780 | 100 % | 209 | 72.2 | 136 | 7,951 / 10,299 | 380 | — |
| Full · RSA-2048 · X25519 | NURL | 645 | 100 % | 1,545 | 1,368 | 177 | 18,365 / 85,443 | 1,647 | — |
| Full · RSA-2048 · X25519 | RUST | 2,111 | 100 % | 472 | 338 | 134 | 14,508 / 25,135 | 548 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 95,238 | 100 % | 10.5 | 694 / 794 | 1.61 |
| NURL | plaintext | 112,862 | 100 % | 8.85 | 589 / 675 |  |
| RUST | TLS | 88,540 | 100 % | 11.3 | 732 / 802 | 2.50 |
| RUST | plaintext | 113,990 | 100 % | 8.76 | 569 / 634 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 2,363 | 94 % | 407 | 89.6 | — |
| NURL | chacha | 936 | 90 % | 980 | 522 | — |
| NURL | plain | 4,721 | 86 % | 187 | n/a | — |
| NURL | aes128+ktls | 1,532 | 64 % | 431 | 89.6 | yes |
| RUST | aes128 | 2,156 | 94 % | 446 | 81.4 | — |
| RUST | chacha | 906 | 95 % | 1,077 | 494 | — |
| RUST | plain | 4,629 | 85 % | 188 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,623 | 0.02 | 614 / 668 | 0 |
| full:/ | reqwest | 1,395 | 0.02 | 709 / 771 | 0 |
| resume:/ | http-client | 1,724 | 0.02 | 577 / 635 | 0 |
| resume:/ | reqwest | 1,566 | 0.02 | 632 / 685 | 0 |
| ka:/1k | http-client | 23,939 | 24.5 | 41.0 / 53.0 | 0 |
| ka:/1k | reqwest | 15,525 | 15.9 | 62.0 / 81.0 | 0 |
| ka:/1m | http-client | 1,701 | 1,783 | 587 / 611 | 0 |
| ka:/1m | reqwest | 1,309 | 1,372 | 698 / 1,078 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 15.9 | 8.35 | 53 % |
| X25519 shared | 43.8 | 24.8 | 56 % |
| P-256 ECDH keygen | 37.9 | 10.3 | 27 % |
| P-256 ECDH shared | 111 | 46.8 | 42 % |
| ML-KEM-768 encaps | 27.6 | 15.5 | 56 % |
| ECDSA P-256 sign | 50.9 | 17.6 | 34 % |
| ECDSA P-256 verify | 133 | 56.1 | 42 % |
| RSA-2048 PSS sign | 1,305 | 299 | 23 % |
| HKDF-Expand-Label | 0.16 | 0.37 | 237 % |
| SHA-256 16 KB | 12.2 | 12.4 | 101 % |
| AES-128-GCM seal 16 KB | 1.43 | 1.30 | 91 % |
| ChaCha20-Poly1305 seal 16 KB | 8.35 | 7.91 | 95 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `fbdeb3b3ef29efb94ee0f5838e7762fdcf803ca1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40063743388 |
| NURL | `v0.77.2-30-gfbdeb3b3` |
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
