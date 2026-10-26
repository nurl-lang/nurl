# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-26T09:49:16Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 866/s | 1,152/s | 75 % | behind | server CPU 1,152 vs 864 µs/handshake: of the 288 µs gap, 265 µs is primitive crypto (largest: RSA-2048 PSS sign, +248 µs), 22.3 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 2,894/s | 3,842/s | 75 % | behind | server CPU 345 vs 260 µs/handshake: of the 85.0 µs gap, 92.0 µs is primitive crypto (largest: P-256 ECDH shared, +62.8 µs), NURL's protocol / runtime / I/O is 7.06 µs CHEAPER than Rust's |
| 3 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,261 µs | 964 µs | 76 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 3,798/s | 4,578/s | 83 % | behind | server CPU 263 vs 218 µs/handshake: of the 44.7 µs gap, 35.1 µs is primitive crypto (largest: ECDSA P-256 sign, +17.7 µs), 9.66 µs is protocol / runtime / I/O |
| 5 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,476/s | 4,002/s | 87 % | behind | server CPU 287 vs 249 µs/handshake: of the 37.8 µs gap, 40.7 µs is primitive crypto (largest: ECDSA P-256 sign, +17.7 µs), NURL's protocol / runtime / I/O is 2.90 µs CHEAPER than Rust's |
| 6 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 503 µs | 447 µs | 89 % | behind |  |
| 7 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 408 µs | 376 µs | 92 % | behind |  |
| 8 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 282 µs | 266 µs | 94 % | behind |  |
| 9 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 461 µs | 439 µs | 95 % | parity |  |
| 10 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 937 MB/s | 959 MB/s | 98 % | parity | server CPU 953 vs 892 ns/KB; the AEAD alone is 494 vs 433 ns/KB |
| 11 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 69,671/s | 69,245/s | 101 % | parity | not TLS: the HTTP/1.1 server itself |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,140/s | 4,999/s | 103 % | parity | server CPU/handshake 194 vs 200 µs |
| 13 | record layer | Keep-alive 1 KB over TLS — req/s | 60,656/s | 52,882/s | 115 % | ahead | TLS adds 2.07 µs CPU per request on NURL, 4.41 µs on Rust (TLS minus plaintext) |
| 14 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 879 MB/s | 765 MB/s | 115 % | ahead |  |
| 15 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,432 MB/s | 1,227 MB/s | 117 % | ahead | server CPU 388 vs 658 ns/KB; the AEAD alone is 138 vs 247 ns/KB |
| 16 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,504/s | 1,272/s | 118 % | ahead | p50 666 vs 781 µs per request |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,477/s | 1,171/s | 126 % | ahead | p50 677 vs 847 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 12,176/s | 9,323/s | 131 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 3,798 | 100 % | 263 | 94.9 | 168 | 7,635 / 12,650 | 408 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,578 | 100 % | 218 | 59.9 | 158 | 6,998 / 8,947 | 376 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,140 | 100 % | 194 | 59.6 | 134 | 5,781 / 9,285 | 282 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 4,999 | 100 % | 200 | 42.2 | 157 | 6,379 / 7,757 | 266 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 2,894 | 100 % | 345 | 177 | 168 | 4,224 / 19,014 | 503 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,842 | 100 % | 260 | 84.7 | 175 | 9,770 / 12,227 | 447 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,476 | 100 % | 287 | 114 | 173 | 8,034 / 14,439 | 461 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,002 | 100 % | 249 | 73.2 | 176 | 8,045 / 10,029 | 439 | — |
| Full · RSA-2048 · X25519 | NURL | 866 | 100 % | 1,152 | 969 | 183 | 35,235 / 68,691 | 1,261 | — |
| Full · RSA-2048 · X25519 | RUST | 1,152 | 100 % | 864 | 703 | 161 | 27,572 / 40,345 | 964 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 60,656 | 100 % | 16.4 | 1,092 / 1,242 | 2.07 |
| NURL | plaintext | 69,671 | 100 % | 14.4 | 951 / 1,068 |  |
| RUST | TLS | 52,882 | 100 % | 18.8 | 1,227 / 1,350 | 4.41 |
| RUST | plaintext | 69,245 | 100 % | 14.4 | 938 / 1,023 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,432 | 54 % | 388 | 138 | — |
| NURL | chacha | 937 | 87 % | 953 | 494 | — |
| NURL | plain | 3,816 | 90 % | 243 | n/a | — |
| NURL | aes128+ktls | 796 | 65 % | 834 | 138 | yes |
| RUST | aes128 | 1,227 | 79 % | 658 | 247 | — |
| RUST | chacha | 959 | 84 % | 892 | 433 | — |
| RUST | plain | 3,745 | 89 % | 244 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,477 | 0.02 | 677 / 738 | 0 |
| full:/ | reqwest | 1,171 | 0.02 | 847 / 900 | 0 |
| resume:/ | http-client | 1,504 | 0.02 | 666 / 723 | 0 |
| resume:/ | reqwest | 1,272 | 0.02 | 781 / 833 | 0 |
| ka:/1k | http-client | 12,176 | 12.5 | 81.0 / 92.0 | 0 |
| ka:/1k | reqwest | 9,323 | 9.55 | 106 / 117 | 0 |
| ka:/1m | http-client | 838 | 879 | 1,184 / 1,265 | 0 |
| ka:/1m | reqwest | 729 | 765 | 1,415 / 1,778 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 15.1 | 8.70 | 58 % |
| X25519 shared | 42.3 | 28.2 | 67 % |
| P-256 ECDH keygen | 24.9 | 10.3 | 41 % |
| P-256 ECDH shared | 114 | 51.4 | 45 % |
| ML-KEM-768 encaps | 18.9 | 13.3 | 70 % |
| ECDSA P-256 sign | 35.4 | 17.7 | 50 % |
| ECDSA P-256 verify | 136 | 57.9 | 43 % |
| RSA-2048 PSS sign | 909 | 661 | 73 % |
| HKDF-Expand-Label | 0.14 | 0.33 | 244 % |
| SHA-256 16 KB | 10.4 | 10.3 | 99 % |
| AES-128-GCM seal 16 KB | 2.21 | 3.95 | 179 % |
| ChaCha20-Poly1305 seal 16 KB | 7.91 | 6.93 | 88 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `d216fa60484e7af06b58883c02fd606856134080` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40301879941 |
| NURL | `v0.78.0-12-gd216fa60` |
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
