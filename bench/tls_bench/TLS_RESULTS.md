# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-27T15:46:12Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 864/s | 1,155/s | 75 % | **gap** | server CPU 1,155 vs 864 µs/handshake: of the 291 µs gap, 267 µs is primitive crypto (largest: RSA-2048 PSS sign, +249 µs), 23.9 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 2,942/s | 3,878/s | 76 % | behind | server CPU 339 vs 257 µs/handshake: of the 81.8 µs gap, 92.3 µs is primitive crypto (largest: P-256 ECDH shared, +62.9 µs), NURL's protocol / runtime / I/O is 10.5 µs CHEAPER than Rust's |
| 3 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 845 MB/s | 1,071 MB/s | 79 % | behind | server CPU 993 vs 861 ns/KB; the AEAD alone is 503 vs 433 ns/KB |
| 4 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,225 µs | 1,000 µs | 82 % | behind |  |
| 5 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,486/s | 3,942/s | 88 % | behind | server CPU 286 vs 253 µs/handshake: of the 33.2 µs gap, 41.3 µs is primitive crypto (largest: ECDSA P-256 sign, +17.7 µs), NURL's protocol / runtime / I/O is 8.17 µs CHEAPER than Rust's |
| 6 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,136/s | 4,535/s | 91 % | behind | server CPU 241 vs 220 µs/handshake: of the 21.2 µs gap, 35.8 µs is primitive crypto (largest: ECDSA P-256 sign, +17.7 µs), NURL's protocol / runtime / I/O is 14.5 µs CHEAPER than Rust's |
| 7 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 495 µs | 452 µs | 91 % | behind |  |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 462 µs | 424 µs | 92 % | behind |  |
| 9 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 408 µs | 385 µs | 94 % | behind |  |
| 10 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,090/s | 4,991/s | 102 % | parity | server CPU/handshake 196 vs 200 µs |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 300 µs | 309 µs | 103 % | parity |  |
| 12 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 70,934/s | 68,800/s | 103 % | parity | not TLS: the HTTP/1.1 server itself |
| 13 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,360 MB/s | 1,281 MB/s | 106 % | ahead | server CPU 589 vs 711 ns/KB; the AEAD alone is 138 vs 247 ns/KB |
| 14 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,503/s | 1,273/s | 118 % | ahead | p50 667 vs 780 µs per request |
| 15 | record layer | Keep-alive 1 KB over TLS — req/s | 60,607/s | 51,081/s | 119 % | ahead | TLS adds 2.34 µs CPU per request on NURL, 4.96 µs on Rust (TLS minus plaintext) |
| 16 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 860 MB/s | 713 MB/s | 121 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,479/s | 1,167/s | 127 % | ahead | p50 676 vs 850 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 11,880/s | 9,283/s | 128 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,136 | 100 % | 241 | 95.4 | 146 | 8,220 / 10,268 | 408 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,535 | 100 % | 220 | 59.6 | 160 | 8,192 / 10,416 | 385 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,090 | 100 % | 196 | 60.0 | 136 | 6,552 / 7,934 | 300 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 4,991 | 100 % | 200 | 42.0 | 158 | 7,416 / 9,285 | 309 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 2,942 | 100 % | 339 | 177 | 162 | 11,314 / 15,532 | 495 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,878 | 100 % | 257 | 84.6 | 173 | 8,350 / 10,555 | 452 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,486 | 100 % | 286 | 114 | 172 | 9,741 / 12,011 | 462 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 3,942 | 100 % | 253 | 72.9 | 180 | 9,443 / 12,033 | 424 | — |
| Full · RSA-2048 · X25519 | NURL | 864 | 100 % | 1,155 | 971 | 184 | 38,367 / 60,572 | 1,225 | — |
| Full · RSA-2048 · X25519 | RUST | 1,155 | 100 % | 864 | 703 | 161 | 27,524 / 39,906 | 1,000 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 60,607 | 100 % | 16.4 | 1,054 / 1,145 | 2.34 |
| NURL | plaintext | 70,934 | 100 % | 14.1 | 899 / 988 |  |
| RUST | TLS | 51,081 | 100 % | 19.5 | 1,271 / 1,394 | 4.96 |
| RUST | plaintext | 68,800 | 100 % | 14.5 | 945 / 1,028 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,360 | 78 % | 589 | 138 | — |
| NURL | chacha | 845 | 82 % | 993 | 503 | — |
| NURL | plain | 3,378 | 91 % | 276 | n/a | — |
| NURL | aes128+ktls | 813 | 62 % | 787 | 138 | yes |
| RUST | aes128 | 1,281 | 89 % | 711 | 247 | — |
| RUST | chacha | 1,071 | 90 % | 861 | 433 | — |
| RUST | plain | 3,453 | 89 % | 264 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,479 | 0.02 | 676 / 743 | 0 |
| full:/ | reqwest | 1,167 | 0.02 | 850 / 908 | 0 |
| resume:/ | http-client | 1,503 | 0.02 | 667 / 725 | 0 |
| resume:/ | reqwest | 1,273 | 0.02 | 780 / 839 | 0 |
| ka:/1k | http-client | 11,880 | 12.2 | 83.0 / 95.0 | 0 |
| ka:/1k | reqwest | 9,283 | 9.51 | 106 / 119 | 0 |
| ka:/1m | http-client | 820 | 860 | 1,214 / 1,284 | 0 |
| ka:/1m | reqwest | 680 | 713 | 1,457 / 1,546 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 15.1 | 8.70 | 58 % |
| X25519 shared | 42.7 | 28.0 | 66 % |
| P-256 ECDH keygen | 24.9 | 10.3 | 41 % |
| P-256 ECDH shared | 114 | 51.4 | 45 % |
| ML-KEM-768 encaps | 18.8 | 13.3 | 70 % |
| ECDSA P-256 sign | 35.4 | 17.6 | 50 % |
| ECDSA P-256 verify | 137 | 57.9 | 42 % |
| RSA-2048 PSS sign | 911 | 661 | 73 % |
| HKDF-Expand-Label | 0.14 | 0.33 | 239 % |
| SHA-256 16 KB | 10.4 | 10.4 | 100 % |
| AES-128-GCM seal 16 KB | 2.20 | 3.96 | 180 % |
| ChaCha20-Poly1305 seal 16 KB | 8.05 | 6.93 | 86 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `7724410934ad521cd949f86273afd94495f07f4f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40533464240 |
| NURL | `v0.79.0-2-g77244109` |
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
