# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-26T06:45:42Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 2,651/s | 3,905/s | 68 % | **gap** | server CPU 377 vs 256 µs/handshake: of the 121 µs gap, 123 µs is primitive crypto (largest: P-256 ECDH shared, +65.2 µs), NURL's protocol / runtime / I/O is 2.46 µs CHEAPER than Rust's |
| 2 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 859/s | 1,146/s | 75 % | **gap** | server CPU 1,161 vs 870 µs/handshake: of the 290 µs gap, 277 µs is primitive crypto (largest: RSA-2048 PSS sign, +259 µs), 12.8 µs is protocol / runtime / I/O |
| 3 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,277 µs | 978 µs | 77 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 422 µs | 342 µs | 81 % | behind |  |
| 5 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 3,753/s | 4,477/s | 84 % | behind | server CPU 266 vs 223 µs/handshake: of the 43.0 µs gap, 50.7 µs is primitive crypto (largest: ECDSA P-256 sign, +32.6 µs), NURL's protocol / runtime / I/O is 7.77 µs CHEAPER than Rust's |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,360/s | 3,981/s | 84 % | behind | server CPU 297 vs 251 µs/handshake: of the 46.3 µs gap, 56.5 µs is primitive crypto (largest: ECDSA P-256 sign, +32.6 µs), NURL's protocol / runtime / I/O is 10.2 µs CHEAPER than Rust's |
| 7 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 531 µs | 449 µs | 85 % | behind |  |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 479 µs | 470 µs | 98 % | parity |  |
| 9 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 69,096/s | 69,161/s | 100 % | parity | not TLS: the HTTP/1.1 server itself |
| 10 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 784 MB/s | 774 MB/s | 101 % | parity | server CPU 968 vs 1,102 ns/KB; the AEAD alone is 506 vs 433 ns/KB |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,132/s | 4,919/s | 104 % | parity | server CPU/handshake 194 vs 203 µs |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 280 µs | 295 µs | 105 % | ahead |  |
| 13 | record layer | Keep-alive 1 KB over TLS — req/s | 59,857/s | 52,049/s | 115 % | ahead | TLS adds 2.17 µs CPU per request on NURL, 4.69 µs on Rust (TLS minus plaintext) |
| 14 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,462/s | 1,265/s | 116 % | ahead | p50 683 vs 784 µs per request |
| 15 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 869 MB/s | 733 MB/s | 119 % | ahead |  |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,436/s | 1,163/s | 124 % | ahead | p50 694 vs 851 µs per request |
| 17 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,286 MB/s | 999 MB/s | 129 % | ahead | server CPU 506 vs 973 ns/KB; the AEAD alone is 138 vs 247 ns/KB |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 12,112/s | 9,221/s | 131 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 3,753 | 100 % | 266 | 110 | 155 | 7,479 / 14,547 | 422 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,477 | 100 % | 223 | 59.5 | 163 | 8,284 / 10,495 | 342 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,132 | 100 % | 194 | 60.0 | 134 | 5,821 / 9,370 | 280 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 4,919 | 100 % | 203 | 41.9 | 161 | 6,515 / 7,861 | 295 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 2,651 | 100 % | 377 | 208 | 169 | 4,569 / 20,565 | 531 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,905 | 100 % | 256 | 84.5 | 171 | 10,048 / 13,270 | 449 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,360 | 100 % | 297 | 129 | 167 | 7,096 / 16,889 | 479 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 3,981 | 100 % | 251 | 72.9 | 178 | 8,122 / 10,039 | 470 | — |
| Full · RSA-2048 · X25519 | NURL | 859 | 100 % | 1,161 | 981 | 180 | 35,770 / 69,524 | 1,277 | — |
| Full · RSA-2048 · X25519 | RUST | 1,146 | 100 % | 870 | 703 | 167 | 27,812 / 38,122 | 978 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 59,857 | 100 % | 16.6 | 1,107 / 1,263 | 2.17 |
| NURL | plaintext | 69,096 | 100 % | 14.5 | 959 / 1,080 |  |
| RUST | TLS | 52,049 | 100 % | 19.1 | 1,246 / 1,380 | 4.69 |
| RUST | plaintext | 69,161 | 100 % | 14.4 | 939 / 1,025 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,286 | 64 % | 506 | 138 | — |
| NURL | chacha | 784 | 74 % | 968 | 506 | — |
| NURL | plain | 3,949 | 90 % | 232 | n/a | — |
| NURL | aes128+ktls | 800 | 59 % | 759 | 138 | yes |
| RUST | aes128 | 999 | 95 % | 973 | 247 | — |
| RUST | chacha | 774 | 83 % | 1,102 | 433 | — |
| RUST | plain | 3,316 | 88 % | 271 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,436 | 0.02 | 694 / 767 | 0 |
| full:/ | reqwest | 1,163 | 0.02 | 851 / 922 | 0 |
| resume:/ | http-client | 1,462 | 0.02 | 683 / 757 | 0 |
| resume:/ | reqwest | 1,265 | 0.02 | 784 / 853 | 0 |
| ka:/1k | http-client | 12,112 | 12.4 | 82.0 / 95.0 | 0 |
| ka:/1k | reqwest | 9,221 | 9.44 | 106 / 122 | 0 |
| ka:/1m | http-client | 829 | 869 | 1,202 / 1,281 | 0 |
| ka:/1m | reqwest | 699 | 733 | 1,456 / 1,837 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 15.1 | 8.70 | 58 % |
| X25519 shared | 42.7 | 28.0 | 66 % |
| P-256 ECDH keygen | 38.9 | 10.3 | 26 % |
| P-256 ECDH shared | 117 | 51.4 | 44 % |
| ML-KEM-768 encaps | 19.2 | 13.4 | 70 % |
| ECDSA P-256 sign | 50.3 | 17.6 | 35 % |
| ECDSA P-256 verify | 139 | 57.8 | 42 % |
| RSA-2048 PSS sign | 921 | 661 | 72 % |
| HKDF-Expand-Label | 0.14 | 0.32 | 238 % |
| SHA-256 16 KB | 10.4 | 10.3 | 99 % |
| AES-128-GCM seal 16 KB | 2.21 | 3.95 | 179 % |
| ChaCha20-Poly1305 seal 16 KB | 8.10 | 6.93 | 86 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `1566a9ee9e6c542473712408785630d766c08383` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40281251657 |
| NURL | `v0.78.0-5-g1566a9ee` |
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
