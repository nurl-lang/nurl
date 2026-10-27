# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-27T05:51:15Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 2,771/s | 3,814/s | 73 % | **gap** | server CPU 360 vs 262 µs/handshake: of the 98.7 µs gap, 92.7 µs is primitive crypto (largest: P-256 ECDH shared, +63.1 µs), 6.00 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 852/s | 1,144/s | 74 % | **gap** | server CPU 1,172 vs 873 µs/handshake: of the 299 µs gap, 275 µs is primitive crypto (largest: RSA-2048 PSS sign, +257 µs), 23.5 µs is protocol / runtime / I/O |
| 3 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,250 µs | 972 µs | 78 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 3,682/s | 4,498/s | 82 % | behind | server CPU 271 vs 222 µs/handshake: of the 49.3 µs gap, 35.9 µs is primitive crypto (largest: ECDSA P-256 sign, +17.9 µs), 13.5 µs is protocol / runtime / I/O |
| 5 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 495 µs | 406 µs | 82 % | behind |  |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,280/s | 3,988/s | 82 % | behind | server CPU 304 vs 250 µs/handshake: of the 53.8 µs gap, 41.5 µs is primitive crypto (largest: ECDSA P-256 sign, +17.9 µs), 12.3 µs is protocol / runtime / I/O |
| 7 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 389 µs | 344 µs | 88 % | behind |  |
| 8 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 303 µs | 275 µs | 91 % | behind |  |
| 9 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,367 MB/s | 1,475 MB/s | 93 % | behind | server CPU 549 vs 520 ns/KB; the AEAD alone is 139 vs 248 ns/KB |
| 10 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 454 µs | 430 µs | 95 % | behind |  |
| 11 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 69,942/s | 70,717/s | 99 % | parity | not TLS: the HTTP/1.1 server itself |
| 12 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 817 MB/s | 815 MB/s | 100 % | parity | server CPU 1,065 vs 1,167 ns/KB; the AEAD alone is 498 vs 435 ns/KB |
| 13 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 4,928/s | 4,906/s | 100 % | parity | server CPU/handshake 202 vs 203 µs |
| 14 | record layer | Keep-alive 1 KB over TLS — req/s | 59,955/s | 52,643/s | 114 % | ahead | TLS adds 2.33 µs CPU per request on NURL, 4.81 µs on Rust (TLS minus plaintext) |
| 15 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 884 MB/s | 764 MB/s | 116 % | ahead |  |
| 16 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,497/s | 1,272/s | 118 % | ahead | p50 666 vs 778 µs per request |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,469/s | 1,166/s | 126 % | ahead | p50 678 vs 848 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 12,144/s | 9,428/s | 129 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 3,682 | 100 % | 271 | 95.7 | 175 | 9,973 / 15,724 | 389 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,498 | 100 % | 222 | 59.8 | 162 | 8,225 / 10,524 | 344 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 4,928 | 100 % | 202 | 60.2 | 142 | 6,490 / 11,324 | 303 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 4,906 | 100 % | 203 | 42.1 | 161 | 6,509 / 7,940 | 275 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 2,771 | 100 % | 360 | 178 | 182 | 11,532 / 22,463 | 495 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,814 | 100 % | 262 | 85.0 | 176 | 8,482 / 10,652 | 406 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,280 | 100 % | 304 | 115 | 189 | 9,873 / 17,040 | 454 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 3,988 | 100 % | 250 | 73.2 | 177 | 8,105 / 10,270 | 430 | — |
| Full · RSA-2048 · X25519 | NURL | 852 | 100 % | 1,172 | 981 | 190 | 38,873 / 72,015 | 1,250 | — |
| Full · RSA-2048 · X25519 | RUST | 1,144 | 100 % | 873 | 706 | 167 | 28,027 / 39,140 | 972 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 59,955 | 100 % | 16.6 | 1,063 / 1,161 | 2.33 |
| NURL | plaintext | 69,942 | 100 % | 14.3 | 915 / 1,010 |  |
| RUST | TLS | 52,643 | 100 % | 18.9 | 1,232 / 1,350 | 4.81 |
| RUST | plaintext | 70,717 | 100 % | 14.1 | 918 / 1,004 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,367 | 73 % | 549 | 139 | — |
| NURL | chacha | 817 | 85 % | 1,065 | 498 | — |
| NURL | plain | 4,308 | 88 % | 209 | n/a | — |
| NURL | aes128+ktls | 299 | 24 % | 810 | 139 | yes |
| RUST | aes128 | 1,475 | 75 % | 520 | 248 | — |
| RUST | chacha | 815 | 93 % | 1,167 | 435 | — |
| RUST | plain | 3,780 | 87 % | 235 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,469 | 0.02 | 678 / 755 | 0 |
| full:/ | reqwest | 1,166 | 0.02 | 848 / 917 | 0 |
| resume:/ | http-client | 1,497 | 0.02 | 666 / 739 | 0 |
| resume:/ | reqwest | 1,272 | 0.02 | 778 / 851 | 0 |
| ka:/1k | http-client | 12,144 | 12.4 | 81.0 / 95.0 | 0 |
| ka:/1k | reqwest | 9,428 | 9.65 | 104 / 119 | 0 |
| ka:/1m | http-client | 843 | 884 | 1,179 / 1,267 | 0 |
| ka:/1m | reqwest | 729 | 764 | 1,268 / 1,990 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 15.2 | 8.72 | 57 % |
| X25519 shared | 42.8 | 28.2 | 66 % |
| P-256 ECDH keygen | 25.1 | 10.3 | 41 % |
| P-256 ECDH shared | 115 | 51.8 | 45 % |
| ML-KEM-768 encaps | 19.0 | 13.4 | 70 % |
| ECDSA P-256 sign | 35.5 | 17.7 | 50 % |
| ECDSA P-256 verify | 136 | 58.1 | 43 % |
| RSA-2048 PSS sign | 921 | 664 | 72 % |
| HKDF-Expand-Label | 0.14 | 0.33 | 240 % |
| SHA-256 16 KB | 10.4 | 10.4 | 100 % |
| AES-128-GCM seal 16 KB | 2.23 | 3.97 | 179 % |
| ChaCha20-Poly1305 seal 16 KB | 7.97 | 6.95 | 87 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `bae01bf283cb6fd386de094818c242b7abeed163` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40457215719 |
| NURL | `v0.78.0-41-gbae01bf2` |
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
