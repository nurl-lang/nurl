# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-23T14:20:41Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 0.07/s | 574/s | 0 % | **major gap** | under 50 handshakes completed in the window; the server's primitives alone cost 450,636 vs 703 µs per handshake |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,521,217 µs | 959 µs | 0 % | **major gap** |  |
| 3 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 23.9/s | 1,302/s | 2 % | **major gap** | p50 41,996 vs 762 µs per request |
| 4 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 23.9/s | 1,201/s | 2 % | **major gap** | p50 41,978 vs 827 µs per request |
| 5 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 2,080/s | 3,905/s | 53 % | **gap** | server CPU 479 vs 255 µs/handshake: of the 224 µs gap, 221 µs is primitive crypto (largest: P-256 ECDH shared, +143 µs), 2.73 µs is protocol / runtime / I/O |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 2,759/s | 4,105/s | 67 % | **gap** | server CPU 361 vs 243 µs/handshake: of the 118 µs gap, 93.0 µs is primitive crypto (largest: ECDSA P-256 sign, +36.9 µs), 25.4 µs is protocol / runtime / I/O |
| 7 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 513 µs | 353 µs | 69 % | **gap** |  |
| 8 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 3,397/s | 4,652/s | 73 % | **gap** | server CPU 294 vs 215 µs/handshake: of the 79.0 µs gap, 78.6 µs is primitive crypto (largest: ECDSA P-256 sign, +36.9 µs), 0.40 µs is protocol / runtime / I/O |
| 9 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 696 MB/s | 948 MB/s | 73 % | **gap** | server CPU 1,409 vs 1,006 ns/KB; the AEAD alone is 696 vs 433 ns/KB |
| 10 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 4,210/s | 5,139/s | 82 % | behind | server CPU 237 vs 194 µs/handshake: of the 42.8 µs gap, 41.7 µs is primitive crypto (largest: X25519 shared, +14.8 µs), 1.11 µs is protocol / runtime / I/O |
| 11 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 637 µs | 540 µs | 85 % | behind |  |
| 12 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 72,803/s | 72,314/s | 101 % | parity | not TLS: the HTTP/1.1 server itself |
| 13 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 522 µs | 544 µs | 104 % | parity |  |
| 14 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 292 µs | 336 µs | 115 % | ahead |  |
| 15 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 879 MB/s | 757 MB/s | 116 % | ahead |  |
| 16 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,215 MB/s | 1,035 MB/s | 117 % | ahead | server CPU 565 vs 880 ns/KB; the AEAD alone is 138 vs 247 ns/KB |
| 17 | record layer | Keep-alive 1 KB over TLS — req/s | 63,138/s | 52,863/s | 119 % | ahead | TLS adds 2.04 µs CPU per request on NURL, 5.05 µs on Rust (TLS minus plaintext) |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 13,206/s | 10,143/s | 130 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 3,397 | 100 % | 294 | 138 | 155 | 3,658 / 15,935 | 513 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,652 | 100 % | 215 | 59.6 | 155 | 6,894 / 8,801 | 353 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 4,210 | 100 % | 237 | 83.7 | 153 | 7,150 / 11,873 | 292 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 5,139 | 100 % | 194 | 42.0 | 152 | 6,222 / 7,599 | 336 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 2,080 | 100 % | 479 | 306 | 173 | 6,281 / 27,732 | 637 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,905 | 100 % | 255 | 84.6 | 171 | 8,252 / 10,576 | 540 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 2,759 | 100 % | 361 | 166 | 195 | 11,076 / 21,686 | 522 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,105 | 100 % | 243 | 72.9 | 170 | 7,833 / 9,994 | 544 | — |
| Full · RSA-2048 · X25519 | NURL | 0.07 ‡ | 100 % | n/a | 450,636 | n/a | 1,575,747 / 1,575,747 | 1,521,217 | — |
| Full · RSA-2048 · X25519 | RUST | 574 † | 50 % | 872 | 703 | 169 | 54,440 / 100,397 | 959 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 63,138 | 100 % | 15.8 | 1,047 / 1,194 | 2.04 |
| NURL | plaintext | 72,803 | 100 % | 13.7 | 912 / 1,029 |  |
| RUST | TLS | 52,863 | 100 % | 18.9 | 1,232 / 1,342 | 5.05 |
| RUST | plaintext | 72,314 | 100 % | 13.8 | 898 / 997 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,215 | 67 % | 565 | 138 | — |
| NURL | chacha | 696 | 96 % | 1,409 | 696 | — |
| NURL | plain | 3,676 | 89 % | 249 | n/a | — |
| NURL | aes128+ktls | 529 | 37 % | 712 | 138 | yes |
| RUST | aes128 | 1,035 | 89 % | 880 | 247 | — |
| RUST | chacha | 948 | 93 % | 1,006 | 433 | — |
| RUST | plain | 3,790 | 89 % | 241 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 23.9 | 0.00 | 41,978 / 42,104 | 0 |
| full:/ | reqwest | 1,201 | 0.02 | 827 / 879 | 0 |
| resume:/ | http-client | 23.9 | 0.00 | 41,996 / 42,140 | 0 |
| resume:/ | reqwest | 1,302 | 0.02 | 762 / 823 | 0 |
| ka:/1k | http-client | 13,206 | 13.5 | 74.0 / 84.0 | 0 |
| ka:/1k | reqwest | 10,143 | 10.4 | 97.0 / 111 | 0 |
| ka:/1m | http-client | 839 | 879 | 1,182 / 1,242 | 0 |
| ka:/1m | reqwest | 722 | 757 | 1,460 / 1,663 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 22.6 | 8.70 | 39 % |
| X25519 shared | 42.9 | 28.0 | 65 % |
| P-256 ECDH keygen | 38.7 | 10.3 | 27 % |
| P-256 ECDH shared | 195 | 51.4 | 26 % |
| ML-KEM-768 encaps | 27.7 | 13.3 | 48 % |
| ECDSA P-256 sign | 54.6 | 17.7 | 32 % |
| ECDSA P-256 verify | 252 | 57.7 | 23 % |
| RSA-2048 PSS sign | 450,553 | 661 | 0 % |
| HKDF-Expand-Label | 1.14 | 0.33 | 29 % |
| SHA-256 16 KB | 66.7 | 10.3 | 16 % |
| AES-128-GCM seal 16 KB | 2.21 | 3.96 | 179 % |
| ChaCha20-Poly1305 seal 16 KB | 11.1 | 6.93 | 62 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `955ab9fca1f6af625aadf005537a0590aa0430ef` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39968148820 |
| NURL | `v0.77.2-3-g955ab9fc` |
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
