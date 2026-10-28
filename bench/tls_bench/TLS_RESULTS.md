# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-28T03:40:07Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 873/s | 1,146/s | 76 % | behind | server CPU 1,143 vs 871 µs/handshake: of the 272 µs gap, 267 µs is primitive crypto (largest: RSA-2048 PSS sign, +249 µs), 4.79 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 2,937/s | 3,846/s | 76 % | behind | server CPU 340 vs 260 µs/handshake: of the 80.1 µs gap, 92.1 µs is primitive crypto (largest: P-256 ECDH shared, +62.8 µs), NURL's protocol / runtime / I/O is 12.0 µs CHEAPER than Rust's |
| 3 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,236 µs | 962 µs | 78 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 496 µs | 405 µs | 82 % | behind |  |
| 5 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,505/s | 3,996/s | 88 % | behind | server CPU 285 vs 250 µs/handshake: of the 35.0 µs gap, 41.4 µs is primitive crypto (largest: ECDSA P-256 sign, +17.8 µs), NURL's protocol / runtime / I/O is 6.44 µs CHEAPER than Rust's |
| 6 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,071/s | 4,554/s | 89 % | behind | server CPU 245 vs 219 µs/handshake: of the 26.0 µs gap, 35.8 µs is primitive crypto (largest: ECDSA P-256 sign, +17.8 µs), NURL's protocol / runtime / I/O is 9.82 µs CHEAPER than Rust's |
| 7 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 454 µs | 416 µs | 92 % | behind |  |
| 8 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 414 µs | 388 µs | 94 % | behind |  |
| 9 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 308 µs | 311 µs | 101 % | parity |  |
| 10 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,064/s | 5,007/s | 101 % | parity | server CPU/handshake 197 vs 199 µs |
| 11 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 73,271/s | 69,898/s | 105 % | parity | not TLS: the HTTP/1.1 server itself |
| 12 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 863 MB/s | 823 MB/s | 105 % | parity | server CPU 1,089 vs 1,188 ns/KB; the AEAD alone is 505 vs 434 ns/KB |
| 13 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,493/s | 1,263/s | 118 % | ahead | p50 671 vs 788 µs per request |
| 14 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,396 MB/s | 1,177 MB/s | 119 % | ahead | server CPU 551 vs 820 ns/KB; the AEAD alone is 138 vs 247 ns/KB |
| 15 | record layer | Keep-alive 1 KB over TLS — req/s | 62,235/s | 51,891/s | 120 % | ahead | TLS adds 2.36 µs CPU per request on NURL, 4.92 µs on Rust (TLS minus plaintext) |
| 16 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 925 MB/s | 762 MB/s | 121 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,464/s | 1,158/s | 126 % | ahead | p50 685 vs 858 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 15,136/s | 10,987/s | 138 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,071 | 100 % | 245 | 95.4 | 150 | 8,354 / 10,306 | 414 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,554 | 100 % | 219 | 59.6 | 159 | 7,029 / 8,860 | 388 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,064 | 100 % | 197 | 60.0 | 137 | 6,593 / 7,924 | 308 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 5,007 | 100 % | 199 | 42.0 | 157 | 7,418 / 9,317 | 311 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 2,937 | 100 % | 340 | 177 | 163 | 11,325 / 15,674 | 496 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,846 | 100 % | 260 | 84.7 | 175 | 8,430 / 10,511 | 405 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,505 | 100 % | 285 | 114 | 170 | 9,660 / 12,051 | 454 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 3,996 | 100 % | 250 | 72.9 | 177 | 8,082 / 10,228 | 416 | — |
| Full · RSA-2048 · X25519 | NURL | 873 | 100 % | 1,143 | 972 | 172 | 38,286 / 54,971 | 1,236 | — |
| Full · RSA-2048 · X25519 | RUST | 1,146 | 100 % | 871 | 704 | 167 | 27,782 / 39,455 | 962 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 62,235 | 100 % | 16.0 | 1,028 / 1,144 | 2.36 |
| NURL | plaintext | 73,271 | 100 % | 13.6 | 877 / 957 |  |
| RUST | TLS | 51,891 | 100 % | 19.2 | 1,248 / 1,319 | 4.92 |
| RUST | plaintext | 69,898 | 100 % | 14.3 | 939 / 996 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,396 | 75 % | 551 | 138 | — |
| NURL | chacha | 863 | 92 % | 1,089 | 505 | — |
| NURL | plain | 4,061 | 93 % | 234 | n/a | — |
| NURL | aes128+ktls | 929 | 65 % | 714 | 138 | yes |
| RUST | aes128 | 1,177 | 94 % | 820 | 247 | — |
| RUST | chacha | 823 | 95 % | 1,188 | 434 | — |
| RUST | plain | 4,501 | 92 % | 208 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,464 | 0.02 | 685 / 727 | 0 |
| full:/ | reqwest | 1,158 | 0.02 | 858 / 895 | 0 |
| resume:/ | http-client | 1,493 | 0.02 | 671 / 713 | 0 |
| resume:/ | reqwest | 1,263 | 0.02 | 788 / 824 | 0 |
| ka:/1k | http-client | 15,136 | 15.5 | 63.0 / 99.0 | 0 |
| ka:/1k | reqwest | 10,987 | 11.3 | 86.0 / 123 | 0 |
| ka:/1m | http-client | 882 | 925 | 1,129 / 1,233 | 0 |
| ka:/1m | reqwest | 727 | 762 | 1,350 / 1,561 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 15.1 | 8.70 | 57 % |
| X25519 shared | 42.7 | 28.0 | 66 % |
| P-256 ECDH keygen | 25.0 | 10.3 | 41 % |
| P-256 ECDH shared | 114 | 51.4 | 45 % |
| ML-KEM-768 encaps | 18.9 | 13.3 | 70 % |
| ECDSA P-256 sign | 35.4 | 17.6 | 50 % |
| ECDSA P-256 verify | 136 | 57.9 | 42 % |
| RSA-2048 PSS sign | 912 | 662 | 73 % |
| HKDF-Expand-Label | 0.14 | 0.33 | 246 % |
| SHA-256 16 KB | 10.4 | 10.4 | 100 % |
| AES-128-GCM seal 16 KB | 2.21 | 3.95 | 179 % |
| ChaCha20-Poly1305 seal 16 KB | 8.08 | 6.95 | 86 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `c62921ec56d1d09741205e022e46c5d74ae88167` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40627540554 |
| NURL | `v0.79.1-8-gc62921ec` |
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
