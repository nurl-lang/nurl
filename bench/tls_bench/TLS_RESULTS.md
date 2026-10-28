# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-28T08:47:50Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 847 MB/s | 1,054 MB/s | 80 % | behind | server CPU 1,102 vs 917 ns/KB; the AEAD alone is 611 vs 542 ns/KB |
| 2 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 387 µs | 323 µs | 83 % | behind |  |
| 3 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 4,488/s | 5,168/s | 87 % | behind | server CPU 222 vs 193 µs/handshake: of the 29.1 µs gap, 31.3 µs is primitive crypto (largest: P-256 ECDH shared, +27.0 µs), NURL's protocol / runtime / I/O is 2.15 µs CHEAPER than Rust's |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 361 µs | 322 µs | 89 % | behind |  |
| 5 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,001/s | 2,120/s | 94 % | behind | server CPU 499 vs 471 µs/handshake: of the 27.4 µs gap, 24.2 µs is primitive crypto (largest: RSA-2048 PSS sign, +22.1 µs), 3.14 µs is protocol / runtime / I/O |
| 6 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 564 µs | 536 µs | 95 % | parity |  |
| 7 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 5,117/s | 5,296/s | 97 % | parity | server CPU 195 vs 188 µs/handshake: of the 6.59 µs gap, 8.36 µs is primitive crypto (largest: ML-KEM-768 encaps, +3.89 µs), NURL's protocol / runtime / I/O is 1.78 µs CHEAPER than Rust's |
| 8 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 122,776/s | 121,740/s | 101 % | parity | not TLS: the HTTP/1.1 server itself |
| 9 | record layer | Keep-alive 1 KB over TLS — req/s | 107,496/s | 105,840/s | 102 % | parity | TLS adds 1.11 µs CPU per request on NURL, 1.21 µs on Rust (TLS minus plaintext) |
| 10 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 6,266/s | 6,135/s | 102 % | parity | server CPU/handshake 159 vs 162 µs |
| 11 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 2,423 MB/s | 2,345 MB/s | 103 % | parity | server CPU 396 vs 409 ns/KB; the AEAD alone is 78.6 vs 73.2 ns/KB |
| 12 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 264 µs | 277 µs | 105 % | parity |  |
| 13 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 8,008/s | 7,323/s | 109 % | ahead | server CPU/handshake 125 vs 136 µs |
| 14 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 185 µs | 205 µs | 111 % | ahead |  |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,950/s | 1,571/s | 124 % | ahead | p50 511 vs 632 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,863/s | 1,377/s | 135 % | ahead | p50 535 vs 720 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 2,069 MB/s | 1,359 MB/s | 152 % | ahead |  |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 33,250/s | 20,282/s | 164 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 6,266 | 100 % | 159 | 63.1 | 96.2 | 5,477 / 6,773 | 264 | — |
| Full · ECDSA P-256 · X25519 | RUST | 6,135 | 100 % | 162 | 58.6 | 104 | 5,561 / 8,564 | 277 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 8,008 | 100 % | 125 | 41.5 | 83.1 | 4,162 / 5,167 | 185 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 7,323 | 100 % | 136 | 39.4 | 96.9 | 5,289 / 7,247 | 205 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 4,488 | 100 % | 222 | 116 | 106 | 7,582 / 10,347 | 361 | — |
| Full · ECDSA P-256 · P-256 | RUST | 5,168 | 100 % | 193 | 84.9 | 108 | 7,009 / 10,046 | 322 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 5,117 | 100 % | 195 | 81.9 | 113 | 6,702 / 8,399 | 387 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 5,296 | 100 % | 188 | 73.5 | 115 | 6,752 / 10,004 | 323 | — |
| Full · RSA-2048 · X25519 | NURL | 2,001 | 100 % | 499 | 416 | 83.0 | 16,714 / 23,394 | 564 | — |
| Full · RSA-2048 · X25519 | RUST | 2,120 | 100 % | 471 | 392 | 79.8 | 14,878 / 26,577 | 536 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 107,496 | 100 % | 9.26 | 593 / 673 | 1.11 |
| NURL | plaintext | 122,776 | 100 % | 8.14 | 521 / 580 |  |
| RUST | TLS | 105,840 | 100 % | 9.42 | 611 / 686 | 1.21 |
| RUST | plaintext | 121,740 | 100 % | 8.21 | 533 / 594 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 2,423 | 94 % | 396 | 78.6 | — |
| NURL | chacha | 847 | 91 % | 1,102 | 611 | — |
| NURL | plain | 5,358 | 93 % | 177 | n/a | — |
| NURL | aes128+ktls | 1,732 | 64 % | 378 | 78.6 | yes |
| RUST | aes128 | 2,345 | 94 % | 409 | 73.2 | — |
| RUST | chacha | 1,054 | 94 % | 917 | 542 | — |
| RUST | plain | 5,111 | 89 % | 179 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,863 | 0.03 | 535 / 594 | 0 |
| full:/ | reqwest | 1,377 | 0.02 | 720 / 810 | 0 |
| resume:/ | http-client | 1,950 | 0.03 | 511 / 570 | 0 |
| resume:/ | reqwest | 1,571 | 0.02 | 632 / 686 | 0 |
| ka:/1k | http-client | 33,250 | 34.0 | 29.0 / 43.0 | 0 |
| ka:/1k | reqwest | 20,282 | 20.8 | 47.0 / 68.0 | 0 |
| ka:/1m | http-client | 1,973 | 2,069 | 508 / 534 | 0 |
| ka:/1m | reqwest | 1,296 | 1,359 | 721 / 1,099 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 11.2 | 8.59 | 77 % |
| X25519 shared | 28.0 | 25.6 | 91 % |
| P-256 ECDH keygen | 16.4 | 11.6 | 71 % |
| P-256 ECDH shared | 75.9 | 48.9 | 64 % |
| ML-KEM-768 encaps | 18.8 | 14.9 | 79 % |
| ECDSA P-256 sign | 21.5 | 19.2 | 89 % |
| ECDSA P-256 verify | 87.3 | 64.3 | 74 % |
| RSA-2048 PSS sign | 374 | 352 | 94 % |
| HKDF-Expand-Label | 0.15 | 0.33 | 221 % |
| SHA-256 16 KB | 11.3 | 11.2 | 99 % |
| AES-128-GCM seal 16 KB | 1.26 | 1.17 | 93 % |
| ChaCha20-Poly1305 seal 16 KB | 9.78 | 8.68 | 89 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | `INTEL(R) XEON(R) PLATINUM 8573C` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `f49b549b03017cd36a86add0c6f844aad6e98618` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40658841891 |
| NURL | `v0.79.1-29-gf49b549b` |
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
