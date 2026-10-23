# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-23T21:46:31Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 653/s | 2,585/s | 25 % | **major gap** | server CPU 1,530 vs 386 µs/handshake: of the 1,144 µs gap, 1,104 µs is primitive crypto (largest: RSA-2048 PSS sign, +1,082 µs), 40.1 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,597 µs | 489 µs | 31 % | **major gap** |  |
| 3 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,432/s | 5,227/s | 66 % | **gap** | server CPU 291 vs 191 µs/handshake: of the 100.0 µs gap, 106 µs is primitive crypto (largest: P-256 ECDH shared, +54.8 µs), NURL's protocol / runtime / I/O is 5.54 µs CHEAPER than Rust's |
| 4 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,645/s | 6,260/s | 74 % | **gap** | server CPU 215 vs 159 µs/handshake: of the 55.4 µs gap, 50.4 µs is primitive crypto (largest: ECDSA P-256 sign, +28.2 µs), 4.97 µs is protocol / runtime / I/O |
| 5 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,936/s | 5,302/s | 74 % | **gap** | server CPU 254 vs 188 µs/handshake: of the 65.3 µs gap, 60.7 µs is primitive crypto (largest: ECDSA P-256 sign, +28.2 µs), 4.59 µs is protocol / runtime / I/O |
| 6 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 843 MB/s | 1,030 MB/s | 82 % | behind | server CPU 1,166 vs 930 ns/KB; the AEAD alone is 620 vs 390 ns/KB |
| 7 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 426 µs | 356 µs | 84 % | behind |  |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 413 µs | 350 µs | 85 % | behind |  |
| 9 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 233 µs | 199 µs | 85 % | behind |  |
| 10 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 340 µs | 300 µs | 88 % | behind |  |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 6,440/s | 6,944/s | 93 % | behind | server CPU 155 vs 144 µs/handshake: of the 11.2 µs gap, 22.3 µs is primitive crypto (largest: X25519 shared, +12.6 µs), NURL's protocol / runtime / I/O is 11.0 µs CHEAPER than Rust's |
| 12 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 97,898/s | 100,441/s | 97 % | parity | not TLS: the HTTP/1.1 server itself |
| 13 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 2,006 MB/s | 2,035 MB/s | 99 % | parity | server CPU 466 vs 449 ns/KB; the AEAD alone is 119 vs 89.9 ns/KB |
| 14 | record layer | Keep-alive 1 KB over TLS — req/s | 87,656/s | 85,163/s | 103 % | parity | TLS adds 1.15 µs CPU per request on NURL, 1.75 µs on Rust (TLS minus plaintext) |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,798/s | 1,613/s | 111 % | ahead | p50 552 vs 615 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,761/s | 1,461/s | 121 % | ahead | p50 565 vs 678 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 1,956 MB/s | 1,550 MB/s | 126 % | ahead |  |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 24,788/s | 18,558/s | 134 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,645 | 100 % | 215 | 102 | 113 | 2,779 / 12,356 | 340 | — |
| Full · ECDSA P-256 · X25519 | RUST | 6,260 | 100 % | 159 | 51.3 | 108 | 5,777 / 8,152 | 300 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 6,440 | 100 % | 155 | 58.3 | 96.6 | 4,641 / 8,060 | 233 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 6,944 | 100 % | 144 | 36.1 | 108 | 4,624 / 6,299 | 199 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,432 | 100 % | 291 | 178 | 113 | 3,540 / 15,133 | 426 | — |
| Full · ECDSA P-256 · P-256 | RUST | 5,227 | 100 % | 191 | 72.4 | 118 | 7,095 / 9,258 | 356 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,936 | 100 % | 254 | 125 | 128 | 3,836 / 15,174 | 413 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 5,302 | 100 % | 188 | 64.4 | 124 | 6,967 / 9,186 | 350 | — |
| Full · RSA-2048 · X25519 | NURL | 653 | 100 % | 1,530 | 1,382 | 148 | 46,301 / 92,243 | 1,597 | — |
| Full · RSA-2048 · X25519 | RUST | 2,585 | 100 % | 386 | 278 | 108 | 12,002 / 19,100 | 489 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 87,656 | 100 % | 11.4 | 754 / 840 | 1.15 |
| NURL | plaintext | 97,898 | 100 % | 10.2 | 679 / 766 |  |
| RUST | TLS | 85,163 | 100 % | 11.7 | 758 / 832 | 1.75 |
| RUST | plaintext | 100,441 | 100 % | 9.96 | 646 / 707 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 2,006 | 91 % | 466 | 119 | — |
| NURL | chacha | 843 | 96 % | 1,166 | 620 | — |
| NURL | plain | 4,813 | 92 % | 195 | n/a | — |
| NURL | aes128+ktls | 1,305 | 71 % | 556 | 119 | yes |
| RUST | aes128 | 2,035 | 89 % | 449 | 89.9 | — |
| RUST | chacha | 1,030 | 94 % | 930 | 390 | — |
| RUST | plain | 4,787 | 88 % | 188 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,761 | 0.02 | 565 / 630 | 0 |
| full:/ | reqwest | 1,461 | 0.02 | 678 / 740 | 0 |
| resume:/ | http-client | 1,798 | 0.03 | 552 / 625 | 0 |
| resume:/ | reqwest | 1,613 | 0.02 | 615 / 666 | 0 |
| ka:/1k | http-client | 24,788 | 25.4 | 39.0 / 52.0 | 0 |
| ka:/1k | reqwest | 18,558 | 19.0 | 52.0 / 67.0 | 0 |
| ka:/1m | http-client | 1,865 | 1,956 | 533 / 578 | 0 |
| ka:/1m | reqwest | 1,478 | 1,550 | 611 / 936 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 19.6 | 7.68 | 39 % |
| X25519 shared | 36.8 | 24.2 | 66 % |
| P-256 ECDH keygen | 33.7 | 8.89 | 26 % |
| P-256 ECDH shared | 98.9 | 44.1 | 45 % |
| ML-KEM-768 encaps | 23.4 | 13.1 | 56 % |
| ECDSA P-256 sign | 43.4 | 15.2 | 35 % |
| ECDSA P-256 verify | 118 | 49.9 | 42 % |
| RSA-2048 PSS sign | 1,324 | 242 | 18 % |
| HKDF-Expand-Label | 0.12 | 0.26 | 217 % |
| SHA-256 16 KB | 9.12 | 9.11 | 100 % |
| AES-128-GCM seal 16 KB | 1.91 | 1.44 | 75 % |
| ChaCha20-Poly1305 seal 16 KB | 9.91 | 6.24 | 63 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 9V74 80-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `327a6fd01b98a854635724e0dc46c8ae8e7ea612` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40028022085 |
| NURL | `v0.77.2-20-g327a6fd0` |
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
