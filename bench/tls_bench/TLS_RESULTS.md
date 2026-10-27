# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-27T11:44:19Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 863/s | 1,144/s | 75 % | behind | server CPU 1,155 vs 872 µs/handshake: of the 284 µs gap, 265 µs is primitive crypto (largest: RSA-2048 PSS sign, +247 µs), 18.6 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 2,896/s | 3,833/s | 76 % | behind | server CPU 344 vs 260 µs/handshake: of the 84.0 µs gap, 92.5 µs is primitive crypto (largest: P-256 ECDH shared, +63.1 µs), NURL's protocol / runtime / I/O is 8.54 µs CHEAPER than Rust's |
| 3 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,247 µs | 1,000 µs | 80 % | behind |  |
| 4 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 859 MB/s | 1,067 MB/s | 81 % | behind | server CPU 1,099 vs 860 ns/KB; the AEAD alone is 495 vs 434 ns/KB |
| 5 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 3,762/s | 4,582/s | 82 % | behind | server CPU 265 vs 218 µs/handshake: of the 47.1 µs gap, 35.5 µs is primitive crypto (largest: ECDSA P-256 sign, +17.8 µs), 11.6 µs is protocol / runtime / I/O |
| 6 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 509 µs | 426 µs | 84 % | behind |  |
| 7 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,321/s | 3,960/s | 84 % | behind | server CPU 300 vs 252 µs/handshake: of the 48.5 µs gap, 41.1 µs is primitive crypto (largest: ECDSA P-256 sign, +17.8 µs), 7.37 µs is protocol / runtime / I/O |
| 8 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 385 µs | 348 µs | 90 % | behind |  |
| 9 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 458 µs | 436 µs | 95 % | parity |  |
| 10 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 69,774/s | 69,515/s | 100 % | parity | not TLS: the HTTP/1.1 server itself |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 303 µs | 309 µs | 102 % | parity |  |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,144/s | 4,967/s | 104 % | parity | server CPU/handshake 194 vs 201 µs |
| 13 | record layer | Keep-alive 1 KB over TLS — req/s | 60,212/s | 52,070/s | 116 % | ahead | TLS adds 2.24 µs CPU per request on NURL, 4.78 µs on Rust (TLS minus plaintext) |
| 14 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 860 MB/s | 740 MB/s | 116 % | ahead |  |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,497/s | 1,270/s | 118 % | ahead | p50 668 vs 781 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,471/s | 1,164/s | 126 % | ahead | p50 679 vs 850 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 12,022/s | 9,276/s | 130 % | ahead |  |
| 18 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,500 MB/s | 1,048 MB/s | 143 % | ahead | server CPU 367 vs 784 ns/KB; the AEAD alone is 138 vs 247 ns/KB |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 3,762 | 100 % | 265 | 95.0 | 170 | 9,482 / 15,202 | 385 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,582 | 100 % | 218 | 59.5 | 158 | 8,470 / 11,228 | 348 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,144 | 100 % | 194 | 59.6 | 134 | 6,125 / 9,697 | 303 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 4,967 | 100 % | 201 | 41.9 | 159 | 6,424 / 7,894 | 309 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 2,896 | 100 % | 344 | 177 | 167 | 11,140 / 21,902 | 509 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,833 | 100 % | 260 | 84.6 | 176 | 8,426 / 10,508 | 426 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,321 | 100 % | 300 | 114 | 187 | 10,007 / 17,437 | 458 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 3,960 | 100 % | 252 | 72.8 | 179 | 8,560 / 11,850 | 436 | — |
| Full · RSA-2048 · X25519 | NURL | 863 | 100 % | 1,155 | 968 | 188 | 39,079 / 71,233 | 1,247 | — |
| Full · RSA-2048 · X25519 | RUST | 1,144 | 100 % | 872 | 703 | 169 | 27,867 / 38,243 | 1,000 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 60,212 | 100 % | 16.6 | 1,059 / 1,154 | 2.24 |
| NURL | plaintext | 69,774 | 100 % | 14.3 | 917 / 996 |  |
| RUST | TLS | 52,070 | 100 % | 19.1 | 1,247 / 1,367 | 4.78 |
| RUST | plaintext | 69,515 | 100 % | 14.4 | 934 / 1,017 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,500 | 54 % | 367 | 138 | — |
| NURL | chacha | 859 | 92 % | 1,099 | 495 | — |
| NURL | plain | 3,743 | 90 % | 246 | n/a | — |
| NURL | aes128+ktls | 731 | 69 % | 969 | 138 | yes |
| RUST | aes128 | 1,048 | 80 % | 784 | 247 | — |
| RUST | chacha | 1,067 | 90 % | 860 | 434 | — |
| RUST | plain | 3,556 | 89 % | 256 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,471 | 0.02 | 679 / 741 | 0 |
| full:/ | reqwest | 1,164 | 0.02 | 850 / 918 | 0 |
| resume:/ | http-client | 1,497 | 0.02 | 668 / 729 | 0 |
| resume:/ | reqwest | 1,270 | 0.02 | 781 / 852 | 0 |
| ka:/1k | http-client | 12,022 | 12.3 | 82.0 / 98.0 | 0 |
| ka:/1k | reqwest | 9,276 | 9.50 | 105 / 128 | 0 |
| ka:/1m | http-client | 820 | 860 | 1,214 / 1,293 | 0 |
| ka:/1m | reqwest | 705 | 740 | 1,288 / 1,450 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 15.1 | 8.69 | 58 % |
| X25519 shared | 42.4 | 28.0 | 66 % |
| P-256 ECDH keygen | 24.9 | 10.3 | 41 % |
| P-256 ECDH shared | 115 | 51.5 | 45 % |
| ML-KEM-768 encaps | 18.9 | 13.3 | 70 % |
| ECDSA P-256 sign | 35.4 | 17.6 | 50 % |
| ECDSA P-256 verify | 137 | 57.9 | 42 % |
| RSA-2048 PSS sign | 908 | 661 | 73 % |
| HKDF-Expand-Label | 0.14 | 0.32 | 240 % |
| SHA-256 16 KB | 10.4 | 10.3 | 100 % |
| AES-128-GCM seal 16 KB | 2.21 | 3.95 | 179 % |
| ChaCha20-Poly1305 seal 16 KB | 7.92 | 6.94 | 88 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `2a99287eda8b8a5255b92f6b0918c7398b774455` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40497810232 |
| NURL | `v0.78.0-49-g2a99287e` |
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
