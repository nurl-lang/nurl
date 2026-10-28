# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-28T04:33:16Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 5,322/s | 7,443/s | 72 % | **gap** | server CPU 188 vs 134 µs/handshake: of the 53.3 µs gap, 56.4 µs is primitive crypto (largest: P-256 ECDH shared, +39.6 µs), NURL's protocol / runtime / I/O is 3.04 µs CHEAPER than Rust's |
| 2 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 229 µs | 175 µs | 76 % | behind |  |
| 3 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 5,988/s | 7,485/s | 80 % | behind | server CPU 167 vs 133 µs/handshake: of the 33.5 µs gap, 22.0 µs is primitive crypto (largest: ECDSA P-256 sign, +10.6 µs), 11.5 µs is protocol / runtime / I/O |
| 4 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,658/s | 3,323/s | 80 % | behind | server CPU 376 vs 301 µs/handshake: of the 74.9 µs gap, 51.1 µs is primitive crypto (largest: RSA-2048 PSS sign, +40.5 µs), 23.8 µs is protocol / runtime / I/O |
| 5 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,219 MB/s | 1,523 MB/s | 80 % | behind | server CPU 806 vs 638 ns/KB; the AEAD alone is 426 vs 361 ns/KB |
| 6 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 7,397/s | 8,798/s | 84 % | behind | server CPU 135 vs 113 µs/handshake: of the 21.6 µs gap, 21.2 µs is primitive crypto (largest: ECDSA P-256 sign, +10.6 µs), 0.38 µs is protocol / runtime / I/O |
| 7 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 279 µs | 247 µs | 89 % | behind |  |
| 8 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 422 µs | 383 µs | 91 % | behind |  |
| 9 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 9,380/s | 9,620/s | 98 % | parity | server CPU 106 vs 104 µs/handshake: of the 2.65 µs gap, 10.6 µs is primitive crypto (largest: X25519 shared, +8.37 µs), NURL's protocol / runtime / I/O is 7.92 µs CHEAPER than Rust's |
| 10 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 122,975/s | 125,682/s | 98 % | parity | not TLS: the HTTP/1.1 server itself |
| 11 | record layer | Keep-alive 1 KB over TLS — req/s | 114,119/s | 116,321/s | 98 % | parity | TLS adds 0.60 µs CPU per request on NURL, 0.61 µs on Rust (TLS minus plaintext) |
| 12 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 254 µs | 277 µs | 109 % | ahead |  |
| 13 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 3,384 MB/s | 2,969 MB/s | 114 % | ahead | server CPU 289 vs 328 ns/KB; the AEAD alone is 49.6 vs 41.8 ns/KB |
| 14 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 35,408/s | 30,389/s | 117 % | ahead |  |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 2,289/s | 1,959/s | 117 % | ahead | p50 428 vs 499 µs per request |
| 16 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 131 µs | 157 µs | 120 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 2,249/s | 1,788/s | 126 % | ahead | p50 437 vs 551 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 2,649 MB/s | 1,881 MB/s | 141 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 7,397 | 100 % | 135 | 55.7 | 79.3 | 4,535 / 6,144 | 229 | — |
| Full · ECDSA P-256 · X25519 | RUST | 8,798 | 100 % | 113 | 34.5 | 78.9 | 3,675 / 5,394 | 175 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 9,380 | 100 % | 106 | 34.3 | 72.1 | 3,554 / 4,238 | 131 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 9,620 | 100 % | 104 | 23.8 | 80.0 | 3,880 / 5,237 | 157 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 5,322 | 100 % | 188 | 106 | 81.6 | 6,316 / 8,397 | 279 | — |
| Full · ECDSA P-256 · P-256 | RUST | 7,443 | 100 % | 134 | 49.5 | 84.7 | 4,985 / 6,516 | 247 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 5,988 | 100 % | 167 | 68.2 | 98.7 | 5,584 / 7,456 | 254 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 7,485 | 100 % | 133 | 46.2 | 87.2 | 5,118 / 6,854 | 277 | — |
| Full · RSA-2048 · X25519 | NURL | 2,658 | 100 % | 376 | 277 | 98.3 | 12,544 / 18,640 | 422 | — |
| Full · RSA-2048 · X25519 | RUST | 3,323 | 100 % | 301 | 226 | 74.5 | 9,474 / 16,767 | 383 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 114,119 | 100 % | 8.74 | 558 / 628 | 0.60 |
| NURL | plaintext | 122,975 | 100 % | 8.13 | 520 / 572 |  |
| RUST | TLS | 116,321 | 100 % | 8.57 | 554 / 617 | 0.61 |
| RUST | plaintext | 125,682 | 100 % | 7.96 | 513 / 716 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 3,384 | 95 % | 289 | 49.6 | — |
| NURL | chacha | 1,219 | 96 % | 806 | 426 | — |
| NURL | plain | 6,487 | 93 % | 147 | n/a | — |
| NURL | aes128+ktls | 1,437 | 96 % | 684 | 49.6 | yes |
| RUST | aes128 | 2,969 | 95 % | 328 | 41.8 | — |
| RUST | chacha | 1,523 | 95 % | 638 | 361 | — |
| RUST | plain | 6,321 | 93 % | 150 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 2,249 | 0.03 | 437 / 517 | 0 |
| full:/ | reqwest | 1,788 | 0.03 | 551 / 643 | 0 |
| resume:/ | http-client | 2,289 | 0.03 | 428 / 549 | 0 |
| resume:/ | reqwest | 1,959 | 0.03 | 499 / 935 | 0 |
| ka:/1k | http-client | 35,408 | 36.3 | 27.0 / 39.0 | 0 |
| ka:/1k | reqwest | 30,389 | 31.1 | 32.0 / 44.0 | 0 |
| ka:/1m | http-client | 2,526 | 2,649 | 397 / 423 | 0 |
| ka:/1m | reqwest | 1,794 | 1,881 | 454 / 890 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 8.82 | 4.75 | 54 % |
| X25519 shared | 23.9 | 15.5 | 65 % |
| P-256 ECDH keygen | 14.2 | 6.19 | 44 % |
| P-256 ECDH shared | 68.7 | 29.1 | 42 % |
| ML-KEM-768 encaps | 12.5 | 11.7 | 94 % |
| ECDSA P-256 sign | 21.4 | 10.7 | 50 % |
| ECDSA P-256 verify | 82.5 | 33.1 | 40 % |
| RSA-2048 PSS sign | 243 | 203 | 83 % |
| HKDF-Expand-Label | 0.10 | 0.22 | 216 % |
| SHA-256 16 KB | 7.46 | 7.73 | 104 % |
| AES-128-GCM seal 16 KB | 0.79 | 0.67 | 84 % |
| ChaCha20-Poly1305 seal 16 KB | 6.82 | 5.77 | 85 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | `AMD EPYC 9V45 96-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `da5aacbfbb307d0a1aa4f502394df0c540a1c400` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40632618194 |
| NURL | `v0.79.1-12-gda5aacbf` |
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
