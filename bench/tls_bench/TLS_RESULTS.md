# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-24T06:28:57Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 561/s | 1,151/s | 49 % | **gap** | server CPU 1,778 vs 866 µs/handshake: of the 912 µs gap, 891 µs is primitive crypto (largest: RSA-2048 PSS sign, +869 µs), 20.8 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,899 µs | 967 µs | 51 % | **gap** |  |
| 3 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 2,611/s | 3,844/s | 68 % | **gap** | server CPU 382 vs 260 µs/handshake: of the 123 µs gap, 121 µs is primitive crypto (largest: P-256 ECDH shared, +63.2 µs), 1.50 µs is protocol / runtime / I/O |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 543 µs | 443 µs | 82 % | behind |  |
| 5 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,309/s | 4,006/s | 83 % | behind | server CPU 301 vs 249 µs/handshake: of the 52.2 µs gap, 60.1 µs is primitive crypto (largest: ECDSA P-256 sign, +32.6 µs), NURL's protocol / runtime / I/O is 7.88 µs CHEAPER than Rust's |
| 6 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 3,800/s | 4,585/s | 83 % | behind | server CPU 262 vs 218 µs/handshake: of the 45.0 µs gap, 54.3 µs is primitive crypto (largest: ECDSA P-256 sign, +32.6 µs), NURL's protocol / runtime / I/O is 9.34 µs CHEAPER than Rust's |
| 7 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 518 µs | 459 µs | 89 % | behind |  |
| 8 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 421 µs | 380 µs | 90 % | behind |  |
| 9 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 841 MB/s | 928 MB/s | 91 % | behind | server CPU 1,024 vs 1,044 ns/KB; the AEAD alone is 503 vs 435 ns/KB |
| 10 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 306 µs | 305 µs | 100 % | parity |  |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 4,959/s | 4,966/s | 100 % | parity | server CPU 201 vs 201 µs/handshake: of the 0.42 µs gap, 21.8 µs is primitive crypto (largest: X25519 shared, +17.9 µs), NURL's protocol / runtime / I/O is 21.3 µs CHEAPER than Rust's |
| 12 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 70,036/s | 69,660/s | 101 % | parity | not TLS: the HTTP/1.1 server itself |
| 13 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,336 MB/s | 1,200 MB/s | 111 % | ahead | server CPU 552 vs 803 ns/KB; the AEAD alone is 140 vs 247 ns/KB |
| 14 | record layer | Keep-alive 1 KB over TLS — req/s | 60,121/s | 52,463/s | 115 % | ahead | TLS adds 2.30 µs CPU per request on NURL, 4.63 µs on Rust (TLS minus plaintext) |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,468/s | 1,270/s | 116 % | ahead | p50 681 vs 781 µs per request |
| 16 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 868 MB/s | 712 MB/s | 122 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,434/s | 1,169/s | 123 % | ahead | p50 695 vs 849 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 12,217/s | 9,329/s | 131 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 3,800 | 100 % | 262 | 114 | 148 | 5,781 / 14,297 | 421 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,585 | 100 % | 218 | 59.7 | 158 | 6,975 / 8,975 | 380 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 4,959 | 100 % | 201 | 63.8 | 137 | 6,053 / 9,634 | 306 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 4,966 | 100 % | 201 | 42.0 | 159 | 6,432 / 7,774 | 305 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 2,611 | 100 % | 382 | 206 | 176 | 10,878 / 22,594 | 543 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,844 | 100 % | 260 | 84.9 | 175 | 8,410 / 10,423 | 443 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,309 | 100 % | 301 | 133 | 168 | 4,568 / 16,910 | 518 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,006 | 100 % | 249 | 73.1 | 176 | 8,042 / 10,090 | 459 | — |
| Full · RSA-2048 · X25519 | NURL | 561 | 100 % | 1,778 | 1,592 | 185 | 54,125 / 107,084 | 1,899 | — |
| Full · RSA-2048 · X25519 | RUST | 1,151 | 100 % | 866 | 702 | 165 | 27,624 / 40,323 | 967 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 60,121 | 100 % | 16.6 | 1,100 / 1,252 | 2.30 |
| NURL | plaintext | 70,036 | 100 % | 14.3 | 946 / 1,063 |  |
| RUST | TLS | 52,463 | 100 % | 19.0 | 1,239 / 1,363 | 4.63 |
| RUST | plaintext | 69,660 | 100 % | 14.4 | 933 / 1,022 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,336 | 72 % | 552 | 140 | — |
| NURL | chacha | 841 | 84 % | 1,024 | 503 | — |
| NURL | plain | 3,800 | 89 % | 240 | n/a | — |
| NURL | aes128+ktls | 818 | 70 % | 879 | 140 | yes |
| RUST | aes128 | 1,200 | 94 % | 803 | 247 | — |
| RUST | chacha | 928 | 95 % | 1,044 | 435 | — |
| RUST | plain | 3,908 | 86 % | 226 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,434 | 0.02 | 695 / 756 | 0 |
| full:/ | reqwest | 1,169 | 0.02 | 849 / 898 | 0 |
| resume:/ | http-client | 1,468 | 0.02 | 681 / 743 | 0 |
| resume:/ | reqwest | 1,270 | 0.02 | 781 / 839 | 0 |
| ka:/1k | http-client | 12,217 | 12.5 | 81.0 / 93.0 | 0 |
| ka:/1k | reqwest | 9,329 | 9.55 | 105 / 119 | 0 |
| ka:/1m | http-client | 828 | 868 | 1,204 / 1,268 | 0 |
| ka:/1m | reqwest | 679 | 712 | 1,462 / 1,516 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 15.5 | 8.70 | 56 % |
| X25519 shared | 46.0 | 28.1 | 61 % |
| P-256 ECDH keygen | 38.7 | 10.4 | 27 % |
| P-256 ECDH shared | 115 | 51.6 | 45 % |
| ML-KEM-768 encaps | 19.2 | 13.3 | 70 % |
| ECDSA P-256 sign | 50.3 | 17.7 | 35 % |
| ECDSA P-256 verify | 138 | 57.6 | 42 % |
| RSA-2048 PSS sign | 1,529 | 660 | 43 % |
| HKDF-Expand-Label | 0.14 | 0.33 | 232 % |
| SHA-256 16 KB | 10.4 | 10.3 | 99 % |
| AES-128-GCM seal 16 KB | 2.24 | 3.95 | 176 % |
| ChaCha20-Poly1305 seal 16 KB | 8.05 | 6.96 | 86 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `142b2367809621bf1d68119347ad3681e915c167` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40070081866 |
| NURL | `v0.77.2-33-g142b2367` |
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
