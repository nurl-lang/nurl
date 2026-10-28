# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-28T04:12:25Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 303 µs | 211 µs | 70 % | **gap** |  |
| 2 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 5,186/s | 7,211/s | 72 % | **gap** | server CPU 193 vs 138 µs/handshake: of the 54.2 µs gap, 56.3 µs is primitive crypto (largest: P-256 ECDH shared, +39.3 µs), NURL's protocol / runtime / I/O is 2.14 µs CHEAPER than Rust's |
| 3 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,205 MB/s | 1,535 MB/s | 79 % | behind | server CPU 817 vs 632 ns/KB; the AEAD alone is 457 vs 381 ns/KB |
| 4 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 443 µs | 354 µs | 80 % | behind |  |
| 5 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,606/s | 3,190/s | 82 % | behind | server CPU 384 vs 313 µs/handshake: of the 70.4 µs gap, 62.9 µs is primitive crypto (largest: RSA-2048 PSS sign, +51.8 µs), 7.55 µs is protocol / runtime / I/O |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 5,897/s | 7,064/s | 83 % | behind | server CPU 169 vs 141 µs/handshake: of the 27.9 µs gap, 21.8 µs is primitive crypto (largest: ECDSA P-256 sign, +10.3 µs), 6.04 µs is protocol / runtime / I/O |
| 7 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 7,236/s | 8,382/s | 86 % | behind | server CPU 138 vs 119 µs/handshake: of the 18.9 µs gap, 21.4 µs is primitive crypto (largest: ECDSA P-256 sign, +10.3 µs), NURL's protocol / runtime / I/O is 2.50 µs CHEAPER than Rust's |
| 8 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 206 µs | 185 µs | 90 % | behind |  |
| 9 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 248 µs | 231 µs | 93 % | behind |  |
| 10 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 121,408/s | 128,162/s | 95 % | behind | not TLS: the HTTP/1.1 server itself |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 9,049/s | 9,355/s | 97 % | parity | server CPU 110 vs 107 µs/handshake: of the 3.61 µs gap, 11.1 µs is primitive crypto (largest: X25519 shared, +9.04 µs), NURL's protocol / runtime / I/O is 7.46 µs CHEAPER than Rust's |
| 12 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 2,865 MB/s | 2,958 MB/s | 97 % | parity | server CPU 340 vs 330 ns/KB; the AEAD alone is 53.1 vs 43.3 ns/KB |
| 13 | record layer | Keep-alive 1 KB over TLS — req/s | 114,300/s | 115,705/s | 99 % | parity | TLS adds 0.49 µs CPU per request on NURL, 0.81 µs on Rust (TLS minus plaintext) |
| 14 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 2,233/s | 1,930/s | 116 % | ahead | p50 441 vs 511 µs per request |
| 15 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 143 µs | 166 µs | 116 % | ahead |  |
| 16 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 34,597/s | 29,576/s | 117 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 2,208/s | 1,763/s | 125 % | ahead | p50 449 vs 560 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 2,603 MB/s | 1,710 MB/s | 152 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 7,236 | 100 % | 138 | 57.6 | 80.4 | 4,666 / 5,924 | 206 | — |
| Full · ECDSA P-256 · X25519 | RUST | 8,382 | 100 % | 119 | 36.2 | 82.9 | 4,410 / 5,716 | 185 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 9,049 | 100 % | 110 | 36.0 | 74.4 | 3,694 / 4,341 | 143 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 9,355 | 100 % | 107 | 24.9 | 81.9 | 4,040 / 5,408 | 166 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 5,186 | 100 % | 193 | 108 | 84.3 | 6,470 / 8,689 | 303 | — |
| Full · ECDSA P-256 · P-256 | RUST | 7,211 | 100 % | 138 | 52.0 | 86.4 | 4,470 / 6,539 | 211 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 5,897 | 100 % | 169 | 70.4 | 98.8 | 5,712 / 7,367 | 248 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 7,064 | 100 % | 141 | 48.6 | 92.8 | 4,626 / 6,510 | 231 | — |
| Full · RSA-2048 · X25519 | NURL | 2,606 | 100 % | 384 | 299 | 84.7 | 12,777 / 17,434 | 443 | — |
| Full · RSA-2048 · X25519 | RUST | 3,190 | 100 % | 313 | 236 | 77.1 | 9,834 / 17,130 | 354 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 114,300 | 100 % | 8.73 | 555 / 656 | 0.49 |
| NURL | plaintext | 121,408 | 100 % | 8.24 | 527 / 616 |  |
| RUST | TLS | 115,705 | 100 % | 8.62 | 556 / 619 | 0.81 |
| RUST | plaintext | 128,162 | 100 % | 7.80 | 506 / 560 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 2,865 | 95 % | 340 | 53.1 | — |
| NURL | chacha | 1,205 | 96 % | 817 | 457 | — |
| NURL | plain | 6,857 | 93 % | 139 | n/a | — |
| NURL | aes128+ktls | 1,351 | 99 % | 747 | 53.1 | yes |
| RUST | aes128 | 2,958 | 95 % | 330 | 43.3 | — |
| RUST | chacha | 1,535 | 95 % | 632 | 381 | — |
| RUST | plain | 7,024 | 92 % | 134 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 2,208 | 0.03 | 449 / 504 | 0 |
| full:/ | reqwest | 1,763 | 0.02 | 560 / 625 | 0 |
| resume:/ | http-client | 2,233 | 0.03 | 441 / 509 | 0 |
| resume:/ | reqwest | 1,930 | 0.03 | 511 / 572 | 0 |
| ka:/1k | http-client | 34,597 | 35.4 | 28.0 / 40.0 | 0 |
| ka:/1k | reqwest | 29,576 | 30.3 | 32.0 / 45.0 | 0 |
| ka:/1m | http-client | 2,482 | 2,603 | 404 / 433 | 0 |
| ka:/1m | reqwest | 1,631 | 1,710 | 532 / 916 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 9.04 | 5.03 | 56 % |
| X25519 shared | 25.3 | 16.3 | 64 % |
| P-256 ECDH keygen | 15.1 | 6.43 | 42 % |
| P-256 ECDH shared | 70.0 | 30.7 | 44 % |
| ML-KEM-768 encaps | 12.8 | 12.3 | 97 % |
| ECDSA P-256 sign | 21.6 | 11.3 | 52 % |
| ECDSA P-256 verify | 81.4 | 34.5 | 42 % |
| RSA-2048 PSS sign | 263 | 211 | 80 % |
| HKDF-Expand-Label | 0.10 | 0.22 | 224 % |
| SHA-256 16 KB | 7.93 | 7.93 | 100 % |
| AES-128-GCM seal 16 KB | 0.85 | 0.69 | 82 % |
| ChaCha20-Poly1305 seal 16 KB | 7.31 | 6.10 | 83 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | `AMD EPYC 9V45 96-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `ba1e47606d18145db70fd8ed43ce304ea636b7df` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40630618328 |
| NURL | `v0.79.1-11-gba1e4760` |
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
