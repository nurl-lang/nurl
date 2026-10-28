# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-28T08:35:26Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 885/s | 1,146/s | 77 % | behind | server CPU 1,128 vs 871 µs/handshake: of the 257 µs gap, 226 µs is primitive crypto (largest: RSA-2048 PSS sign, +224 µs), 30.9 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,234 µs | 999 µs | 81 % | behind |  |
| 3 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 468 µs | 405 µs | 87 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,684/s | 3,819/s | 96 % | parity | server CPU 271 vs 261 µs/handshake: of the 9.53 µs gap, 31.7 µs is primitive crypto (largest: P-256 ECDH shared, +26.0 µs), NURL's protocol / runtime / I/O is 22.1 µs CHEAPER than Rust's |
| 5 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 67,902/s | 68,156/s | 100 % | parity | not TLS: the HTTP/1.1 server itself |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,973/s | 3,975/s | 100 % | parity | server CPU 251 vs 251 µs/handshake: of the 0.18 µs gap, 10.8 µs is primitive crypto (largest: ML-KEM-768 encaps, +5.70 µs), NURL's protocol / runtime / I/O is 10.6 µs CHEAPER than Rust's |
| 7 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,634/s | 4,513/s | 103 % | parity | server CPU/handshake 215 vs 221 µs |
| 8 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,504 MB/s | 1,401 MB/s | 107 % | ahead | server CPU 451 vs 602 ns/KB; the AEAD alone is 138 vs 247 ns/KB |
| 9 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 423 µs | 462 µs | 109 % | ahead |  |
| 10 | record layer | Keep-alive 1 KB over TLS — req/s | 58,889/s | 53,256/s | 111 % | ahead | TLS adds 2.19 µs CPU per request on NURL, 4.06 µs on Rust (TLS minus plaintext) |
| 11 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 341 µs | 384 µs | 113 % | ahead |  |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,574/s | 4,918/s | 113 % | ahead | server CPU/handshake 179 vs 203 µs |
| 13 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 946 MB/s | 811 MB/s | 117 % | ahead | server CPU 899 vs 1,179 ns/KB; the AEAD alone is 495 vs 435 ns/KB |
| 14 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 253 µs | 306 µs | 121 % | ahead |  |
| 15 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 865 MB/s | 714 MB/s | 121 % | ahead |  |
| 16 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,548/s | 1,260/s | 123 % | ahead | p50 646 vs 787 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 12,045/s | 9,330/s | 129 % | ahead |  |
| 18 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,507/s | 1,161/s | 130 % | ahead | p50 663 vs 853 µs per request |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,634 | 100 % | 215 | 64.7 | 150 | 7,337 / 9,018 | 341 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,513 | 100 % | 221 | 59.6 | 161 | 7,092 / 9,050 | 384 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,574 | 100 % | 179 | 44.2 | 135 | 6,004 / 7,099 | 253 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 4,918 | 100 % | 203 | 42.0 | 161 | 6,488 / 7,902 | 306 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,684 | 100 % | 271 | 116 | 154 | 9,257 / 11,583 | 468 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,819 | 100 % | 261 | 84.6 | 177 | 8,475 / 10,691 | 405 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,973 | 100 % | 251 | 83.7 | 167 | 8,574 / 10,323 | 423 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 3,975 | 100 % | 251 | 73.0 | 178 | 8,111 / 10,192 | 462 | — |
| Full · RSA-2048 · X25519 | NURL | 885 | 100 % | 1,128 | 929 | 198 | 37,560 / 55,889 | 1,234 | — |
| Full · RSA-2048 · X25519 | RUST | 1,146 | 100 % | 871 | 703 | 167 | 27,788 / 40,004 | 999 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 58,889 | 100 % | 16.9 | 1,084 / 1,181 | 2.19 |
| NURL | plaintext | 67,902 | 100 % | 14.7 | 940 / 1,031 |  |
| RUST | TLS | 53,256 | 100 % | 18.7 | 1,219 / 1,384 | 4.06 |
| RUST | plaintext | 68,156 | 100 % | 14.7 | 954 / 1,041 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,504 | 66 % | 451 | 138 | — |
| NURL | chacha | 946 | 83 % | 899 | 495 | — |
| NURL | plain | 3,697 | 89 % | 247 | n/a | — |
| NURL | aes128+ktls | 235 | 19 % | 811 | 138 | yes |
| RUST | aes128 | 1,401 | 82 % | 602 | 247 | — |
| RUST | chacha | 811 | 93 % | 1,179 | 435 | — |
| RUST | plain | 3,319 | 91 % | 280 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,507 | 0.02 | 663 / 733 | 0 |
| full:/ | reqwest | 1,161 | 0.02 | 853 / 913 | 0 |
| resume:/ | http-client | 1,548 | 0.02 | 646 / 714 | 0 |
| resume:/ | reqwest | 1,260 | 0.02 | 787 / 851 | 0 |
| ka:/1k | http-client | 12,045 | 12.3 | 82.0 / 95.0 | 0 |
| ka:/1k | reqwest | 9,330 | 9.55 | 105 / 119 | 0 |
| ka:/1m | http-client | 824 | 865 | 1,208 / 1,286 | 0 |
| ka:/1m | reqwest | 681 | 714 | 1,427 / 1,968 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 11.3 | 8.74 | 78 % |
| X25519 shared | 30.8 | 28.0 | 91 % |
| P-256 ECDH keygen | 16.1 | 10.3 | 64 % |
| P-256 ECDH shared | 77.4 | 51.4 | 66 % |
| ML-KEM-768 encaps | 19.0 | 13.3 | 70 % |
| ECDSA P-256 sign | 20.5 | 17.6 | 86 % |
| ECDSA P-256 verify | 87.3 | 58.0 | 66 % |
| RSA-2048 PSS sign | 885 | 661 | 75 % |
| HKDF-Expand-Label | 0.14 | 0.33 | 244 % |
| SHA-256 16 KB | 10.4 | 10.3 | 99 % |
| AES-128-GCM seal 16 KB | 2.21 | 3.95 | 179 % |
| ChaCha20-Poly1305 seal 16 KB | 7.92 | 6.96 | 88 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `76936505fdda19596b6d7b1250d8a2154f5aaf0b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40657304544 |
| NURL | `v0.79.1-27-g76936505` |
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
