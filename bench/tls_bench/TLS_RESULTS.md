# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-26T18:38:08Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 2,883/s | 3,844/s | 75 % | behind | server CPU 346 vs 259 µs/handshake: of the 86.7 µs gap, 92.0 µs is primitive crypto (largest: P-256 ECDH shared, +62.7 µs), NURL's protocol / runtime / I/O is 5.33 µs CHEAPER than Rust's |
| 2 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 865/s | 1,149/s | 75 % | behind | server CPU 1,154 vs 869 µs/handshake: of the 285 µs gap, 297 µs is primitive crypto (largest: RSA-2048 PSS sign, +279 µs), NURL's protocol / runtime / I/O is 12.3 µs CHEAPER than Rust's |
| 3 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,257 µs | 967 µs | 77 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 517 µs | 404 µs | 78 % | behind |  |
| 5 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 3,804/s | 4,528/s | 84 % | behind | server CPU 262 vs 220 µs/handshake: of the 42.0 µs gap, 35.7 µs is primitive crypto (largest: ECDSA P-256 sign, +17.8 µs), 6.26 µs is protocol / runtime / I/O |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,377/s | 3,992/s | 85 % | behind | server CPU 295 vs 250 µs/handshake: of the 45.3 µs gap, 41.2 µs is primitive crypto (largest: ECDSA P-256 sign, +17.8 µs), 4.10 µs is protocol / runtime / I/O |
| 7 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 933 MB/s | 1,075 MB/s | 87 % | behind | server CPU 973 vs 836 ns/KB; the AEAD alone is 496 vs 433 ns/KB |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 481 µs | 454 µs | 94 % | behind |  |
| 9 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 381 µs | 377 µs | 99 % | parity |  |
| 10 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 69,802/s | 70,237/s | 99 % | parity | not TLS: the HTTP/1.1 server itself |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,128/s | 4,968/s | 103 % | parity | server CPU/handshake 194 vs 201 µs |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 298 µs | 309 µs | 104 % | parity |  |
| 13 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 878 MB/s | 779 MB/s | 113 % | ahead |  |
| 14 | record layer | Keep-alive 1 KB over TLS — req/s | 60,832/s | 53,172/s | 114 % | ahead | TLS adds 2.05 µs CPU per request on NURL, 4.49 µs on Rust (TLS minus plaintext) |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,486/s | 1,269/s | 117 % | ahead | p50 668 vs 778 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,472/s | 1,167/s | 126 % | ahead | p50 677 vs 848 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 12,156/s | 9,384/s | 130 % | ahead |  |
| 18 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,521 MB/s | 1,006 MB/s | 151 % | ahead | server CPU 493 vs 954 ns/KB; the AEAD alone is 138 vs 247 ns/KB |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 3,804 | 100 % | 262 | 95.5 | 167 | 7,620 / 12,612 | 381 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,528 | 100 % | 220 | 59.8 | 161 | 8,191 / 10,352 | 377 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,128 | 100 % | 194 | 60.0 | 134 | 5,794 / 9,278 | 298 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 4,968 | 100 % | 201 | 42.1 | 159 | 6,439 / 7,833 | 309 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 2,883 | 100 % | 346 | 177 | 169 | 4,050 / 12,020 | 517 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,844 | 100 % | 259 | 84.9 | 175 | 8,427 / 10,961 | 404 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,377 | 100 % | 295 | 114 | 181 | 8,460 / 14,857 | 481 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 3,992 | 100 % | 250 | 73.2 | 177 | 8,092 / 10,188 | 454 | — |
| Full · RSA-2048 · X25519 | NURL | 865 | 100 % | 1,154 | 1,000 | 153 | 35,700 / 68,675 | 1,257 | — |
| Full · RSA-2048 · X25519 | RUST | 1,149 | 100 % | 869 | 703 | 166 | 27,809 / 37,540 | 967 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 60,832 | 100 % | 16.4 | 1,089 / 1,240 | 2.05 |
| NURL | plaintext | 69,802 | 100 % | 14.3 | 950 / 1,070 |  |
| RUST | TLS | 53,172 | 100 % | 18.7 | 1,222 / 1,366 | 4.49 |
| RUST | plaintext | 70,237 | 100 % | 14.2 | 925 / 1,013 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,521 | 73 % | 493 | 138 | — |
| NURL | chacha | 933 | 89 % | 973 | 496 | — |
| NURL | plain | 3,405 | 91 % | 274 | n/a | — |
| NURL | aes128+ktls | 145 | 11 % | 798 | 138 | yes |
| RUST | aes128 | 1,006 | 94 % | 954 | 247 | — |
| RUST | chacha | 1,075 | 88 % | 836 | 433 | — |
| RUST | plain | 4,239 | 88 % | 211 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,472 | 0.02 | 677 / 752 | 0 |
| full:/ | reqwest | 1,167 | 0.02 | 848 / 911 | 0 |
| resume:/ | http-client | 1,486 | 0.02 | 668 / 782 | 0 |
| resume:/ | reqwest | 1,269 | 0.02 | 778 / 875 | 0 |
| ka:/1k | http-client | 12,156 | 12.4 | 81.0 / 96.0 | 0 |
| ka:/1k | reqwest | 9,384 | 9.61 | 105 / 119 | 0 |
| ka:/1m | http-client | 837 | 878 | 1,191 / 1,261 | 0 |
| ka:/1m | reqwest | 743 | 779 | 1,283 / 1,570 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 15.2 | 8.70 | 57 % |
| X25519 shared | 42.7 | 28.1 | 66 % |
| P-256 ECDH keygen | 24.9 | 10.3 | 41 % |
| P-256 ECDH shared | 114 | 51.6 | 45 % |
| ML-KEM-768 encaps | 18.9 | 13.4 | 71 % |
| ECDSA P-256 sign | 35.5 | 17.7 | 50 % |
| ECDSA P-256 verify | 136 | 58.1 | 43 % |
| RSA-2048 PSS sign | 940 | 661 | 70 % |
| HKDF-Expand-Label | 0.14 | 0.33 | 242 % |
| SHA-256 16 KB | 10.4 | 10.3 | 99 % |
| AES-128-GCM seal 16 KB | 2.20 | 3.95 | 179 % |
| ChaCha20-Poly1305 seal 16 KB | 7.93 | 6.93 | 87 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `d4714d62ed91dc56d0f13a4e148a53e1d534dd70` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40378793770 |
| NURL | `v0.78.0-32-gd4714d62` |
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
