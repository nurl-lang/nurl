# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-28T09:48:49Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 889/s | 1,155/s | 77 % | behind | server CPU 1,122 vs 864 µs/handshake: of the 258 µs gap, 224 µs is primitive crypto (largest: RSA-2048 PSS sign, +221 µs), 34.9 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,195 µs | 959 µs | 80 % | behind |  |
| 3 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,271 MB/s | 1,523 MB/s | 83 % | behind | server CPU 619 vs 628 ns/KB; the AEAD alone is 139 vs 247 ns/KB |
| 4 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 379 µs | 344 µs | 91 % | behind |  |
| 5 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,694/s | 3,856/s | 96 % | parity | server CPU 270 vs 259 µs/handshake: of the 11.5 µs gap, 31.5 µs is primitive crypto (largest: P-256 ECDH shared, +25.8 µs), NURL's protocol / runtime / I/O is 20.0 µs CHEAPER than Rust's |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 463 µs | 458 µs | 99 % | parity |  |
| 7 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 69,035/s | 69,497/s | 99 % | parity | not TLS: the HTTP/1.1 server itself |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 4,004/s | 4,018/s | 100 % | parity | server CPU 249 vs 248 µs/handshake: of the 0.71 µs gap, 10.8 µs is primitive crypto (largest: ML-KEM-768 encaps, +5.70 µs), NURL's protocol / runtime / I/O is 10.1 µs CHEAPER than Rust's |
| 9 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 825 MB/s | 816 MB/s | 101 % | parity | server CPU 1,047 vs 1,050 ns/KB; the AEAD alone is 508 vs 435 ns/KB |
| 10 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 436 µs | 446 µs | 102 % | parity |  |
| 11 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,706/s | 4,568/s | 103 % | parity | server CPU/handshake 212 vs 218 µs |
| 12 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 870 MB/s | 777 MB/s | 112 % | ahead |  |
| 13 | record layer | Keep-alive 1 KB over TLS — req/s | 60,066/s | 53,213/s | 113 % | ahead | TLS adds 2.11 µs CPU per request on NURL, 4.35 µs on Rust (TLS minus plaintext) |
| 14 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,684/s | 5,026/s | 113 % | ahead | server CPU/handshake 176 vs 198 µs |
| 15 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 249 µs | 286 µs | 115 % | ahead |  |
| 16 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,549/s | 1,272/s | 122 % | ahead | p50 644 vs 779 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 11,969/s | 9,274/s | 129 % | ahead |  |
| 18 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,522/s | 1,169/s | 130 % | ahead | p50 655 vs 847 µs per request |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,706 | 100 % | 212 | 64.8 | 147 | 7,225 / 8,741 | 379 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,568 | 100 % | 218 | 59.7 | 159 | 8,123 / 10,339 | 344 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,684 | 100 % | 176 | 44.3 | 131 | 5,890 / 7,015 | 249 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 5,026 | 100 % | 198 | 42.1 | 156 | 7,364 / 9,281 | 286 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,694 | 100 % | 270 | 116 | 154 | 9,259 / 11,470 | 436 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,856 | 100 % | 259 | 84.8 | 174 | 8,385 / 10,492 | 446 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 4,004 | 100 % | 249 | 83.8 | 165 | 8,502 / 10,301 | 463 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,018 | 100 % | 248 | 73.1 | 175 | 8,021 / 10,219 | 458 | — |
| Full · RSA-2048 · X25519 | NURL | 889 | 100 % | 1,122 | 927 | 196 | 37,368 / 53,557 | 1,195 | — |
| Full · RSA-2048 · X25519 | RUST | 1,155 | 100 % | 864 | 703 | 161 | 27,619 / 38,073 | 959 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 60,066 | 100 % | 16.6 | 1,062 / 1,166 | 2.11 |
| NURL | plaintext | 69,035 | 100 % | 14.5 | 926 / 1,014 |  |
| RUST | TLS | 53,213 | 100 % | 18.7 | 1,227 / 1,385 | 4.35 |
| RUST | plaintext | 69,497 | 100 % | 14.4 | 934 / 1,022 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,271 | 77 % | 619 | 139 | — |
| NURL | chacha | 825 | 84 % | 1,047 | 508 | — |
| NURL | plain | 4,368 | 86 % | 200 | n/a | — |
| NURL | aes128+ktls | 190 | 14 % | 755 | 139 | yes |
| RUST | aes128 | 1,523 | 93 % | 628 | 247 | — |
| RUST | chacha | 816 | 84 % | 1,050 | 435 | — |
| RUST | plain | 3,516 | 92 % | 267 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,522 | 0.02 | 655 / 733 | 0 |
| full:/ | reqwest | 1,169 | 0.02 | 847 / 907 | 0 |
| resume:/ | http-client | 1,549 | 0.02 | 644 / 721 | 0 |
| resume:/ | reqwest | 1,272 | 0.02 | 779 / 847 | 0 |
| ka:/1k | http-client | 11,969 | 12.3 | 82.0 / 98.0 | 0 |
| ka:/1k | reqwest | 9,274 | 9.50 | 106 / 124 | 0 |
| ka:/1m | http-client | 829 | 870 | 1,200 / 1,277 | 0 |
| ka:/1m | reqwest | 741 | 777 | 1,291 / 1,640 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 11.3 | 8.73 | 78 % |
| X25519 shared | 30.8 | 28.1 | 91 % |
| P-256 ECDH keygen | 16.2 | 10.3 | 64 % |
| P-256 ECDH shared | 77.4 | 51.6 | 67 % |
| ML-KEM-768 encaps | 19.0 | 13.3 | 70 % |
| ECDSA P-256 sign | 20.5 | 17.6 | 86 % |
| ECDSA P-256 verify | 87.7 | 57.8 | 66 % |
| RSA-2048 PSS sign | 882 | 661 | 75 % |
| HKDF-Expand-Label | 0.14 | 0.33 | 242 % |
| SHA-256 16 KB | 10.4 | 10.4 | 100 % |
| AES-128-GCM seal 16 KB | 2.22 | 3.96 | 179 % |
| ChaCha20-Poly1305 seal 16 KB | 8.13 | 6.96 | 86 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `340b6760097eea9b951e15b67fb61ca62951bb19` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40666522129 |
| NURL | `v0.79.1-34-g340b6760` |
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
