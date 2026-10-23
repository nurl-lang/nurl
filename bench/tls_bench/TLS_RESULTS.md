# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-23T20:51:45Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 1,023/s | 3,227/s | 32 % | **major gap** | server CPU 976 vs 309 µs/handshake: of the 666 µs gap, 637 µs is primitive crypto (largest: RSA-2048 PSS sign, +615 µs), 29.8 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,039 µs | 384 µs | 37 % | **major gap** |  |
| 3 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 4,282/s | 7,237/s | 59 % | **gap** | server CPU 233 vs 138 µs/handshake: of the 95.2 µs gap, 75.8 µs is primitive crypto (largest: P-256 ECDH shared, +38.0 µs), 19.4 µs is protocol / runtime / I/O |
| 4 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 4,549/s | 7,306/s | 62 % | **gap** | server CPU 219 vs 137 µs/handshake: of the 82.7 µs gap, 47.0 µs is primitive crypto (largest: ECDSA P-256 sign, +20.1 µs), 35.8 µs is protocol / runtime / I/O |
| 5 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 5,707/s | 8,419/s | 68 % | **gap** | server CPU 175 vs 118 µs/handshake: of the 56.5 µs gap, 41.6 µs is primitive crypto (largest: ECDSA P-256 sign, +20.1 µs), 14.9 µs is protocol / runtime / I/O |
| 6 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,020 MB/s | 1,357 MB/s | 75 % | behind | server CPU 966 vs 716 ns/KB; the AEAD alone is 578 vs 366 ns/KB |
| 7 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 332 µs | 255 µs | 77 % | behind |  |
| 8 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 7,209/s | 9,189/s | 78 % | behind | server CPU 138 vs 109 µs/handshake: of the 29.8 µs gap, 21.5 µs is primitive crypto (largest: X25519 shared, +10.4 µs), 8.32 µs is protocol / runtime / I/O |
| 9 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 180 µs | 167 µs | 93 % | behind |  |
| 10 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 233 µs | 219 µs | 94 % | behind |  |
| 11 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 300 µs | 284 µs | 95 % | behind |  |
| 12 | record layer | Keep-alive 1 KB over TLS — req/s | 106,309/s | 107,422/s | 99 % | parity | TLS adds 0.97 µs CPU per request on NURL, 0.93 µs on Rust (TLS minus plaintext) |
| 13 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 118,773/s | 119,764/s | 99 % | parity | not TLS: the HTTP/1.1 server itself |
| 14 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 3,292 MB/s | 3,046 MB/s | 108 % | ahead | server CPU 241 vs 319 ns/KB; the AEAD alone is 51.2 vs 42.6 ns/KB |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 2,055/s | 1,900/s | 108 % | ahead | p50 483 vs 514 µs per request |
| 16 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 29,873/s | 25,949/s | 115 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 2,020/s | 1,747/s | 116 % | ahead | p50 486 vs 552 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 2,749 MB/s | 2,126 MB/s | 129 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 5,707 | 100 % | 175 | 77.2 | 97.8 | 4,961 / 9,945 | 233 | — |
| Full · ECDSA P-256 · X25519 | RUST | 8,419 | 100 % | 118 | 35.5 | 82.9 | 4,394 / 5,769 | 219 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 7,209 | 100 % | 138 | 45.8 | 92.6 | 1,663 / 6,455 | 180 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 9,189 | 100 % | 109 | 24.3 | 84.3 | 3,463 / 5,109 | 167 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 4,282 | 100 % | 233 | 126 | 107 | 6,803 / 13,828 | 332 | — |
| Full · ECDSA P-256 · P-256 | RUST | 7,237 | 100 % | 138 | 50.6 | 87.3 | 4,480 / 6,580 | 255 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 4,549 | 100 % | 219 | 94.8 | 125 | 5,576 / 13,021 | 300 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 7,306 | 100 % | 137 | 47.8 | 88.9 | 5,324 / 7,231 | 284 | — |
| Full · RSA-2048 · X25519 | NURL | 1,023 | 100 % | 976 | 866 | 110 | 29,633 / 58,760 | 1,039 | — |
| Full · RSA-2048 · X25519 | RUST | 3,227 | 100 % | 309 | 229 | 79.9 | 9,694 / 17,219 | 384 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 106,309 | 100 % | 9.38 | 621 / 696 | 0.97 |
| NURL | plaintext | 118,773 | 100 % | 8.41 | 555 / 643 |  |
| RUST | TLS | 107,422 | 100 % | 9.28 | 606 / 644 | 0.93 |
| RUST | plaintext | 119,764 | 100 % | 8.35 | 541 / 589 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 3,292 | 78 % | 241 | 51.2 | — |
| NURL | chacha | 1,020 | 96 % | 966 | 578 | — |
| NURL | plain | 6,348 | 93 % | 150 | n/a | — |
| NURL | aes128+ktls | 1,496 | 77 % | 529 | 51.2 | yes |
| RUST | aes128 | 3,046 | 95 % | 319 | 42.6 | — |
| RUST | chacha | 1,357 | 95 % | 716 | 366 | — |
| RUST | plain | 5,938 | 92 % | 159 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 2,020 | 0.03 | 486 / 756 | 0 |
| full:/ | reqwest | 1,747 | 0.02 | 552 / 1,095 | 0 |
| resume:/ | http-client | 2,055 | 0.03 | 483 / 549 | 0 |
| resume:/ | reqwest | 1,900 | 0.03 | 514 / 862 | 0 |
| ka:/1k | http-client | 29,873 | 30.6 | 32.0 / 43.0 | 0 |
| ka:/1k | reqwest | 25,949 | 26.6 | 37.0 / 51.0 | 0 |
| ka:/1m | http-client | 2,622 | 2,749 | 379 / 441 | 0 |
| ka:/1m | reqwest | 2,028 | 2,126 | 420 / 831 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 14.0 | 4.91 | 35 % |
| X25519 shared | 26.4 | 15.9 | 60 % |
| P-256 ECDH keygen | 22.0 | 6.34 | 29 % |
| P-256 ECDH shared | 67.6 | 29.6 | 44 % |
| ML-KEM-768 encaps | 17.6 | 12.3 | 70 % |
| ECDSA P-256 sign | 31.3 | 11.2 | 36 % |
| ECDSA P-256 verify | 79.8 | 34.1 | 43 % |
| RSA-2048 PSS sign | 820 | 205 | 25 % |
| HKDF-Expand-Label | 0.34 | 0.22 | 63 % |
| SHA-256 16 KB | 39.4 | 7.79 | 20 % |
| AES-128-GCM seal 16 KB | 0.82 | 0.68 | 83 % |
| ChaCha20-Poly1305 seal 16 KB | 9.25 | 5.86 | 63 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 9V45 96-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `c978370b68617cf6dd7d9546784e8d03873c3793` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40021040931 |
| NURL | `v0.77.2-17-gc978370b` |
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
