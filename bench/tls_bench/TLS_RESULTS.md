# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-28T09:01:19Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 884/s | 1,147/s | 77 % | behind | server CPU 1,128 vs 869 µs/handshake: of the 259 µs gap, 220 µs is primitive crypto (largest: RSA-2048 PSS sign, +218 µs), 39.1 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,243 µs | 999 µs | 80 % | behind |  |
| 3 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,235 MB/s | 1,391 MB/s | 89 % | behind | server CPU 686 vs 677 ns/KB; the AEAD alone is 139 vs 247 ns/KB |
| 4 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 375 µs | 354 µs | 94 % | behind |  |
| 5 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,710/s | 3,819/s | 97 % | parity | server CPU 269 vs 261 µs/handshake: of the 7.67 µs gap, 31.7 µs is primitive crypto (largest: P-256 ECDH shared, +26.0 µs), NURL's protocol / runtime / I/O is 24.0 µs CHEAPER than Rust's |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,912/s | 3,965/s | 99 % | parity | server CPU 255 vs 252 µs/handshake: of the 3.42 µs gap, 11.0 µs is primitive crypto (largest: ML-KEM-768 encaps, +5.84 µs), NURL's protocol / runtime / I/O is 7.55 µs CHEAPER than Rust's |
| 7 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 450 µs | 458 µs | 102 % | parity |  |
| 8 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,647/s | 4,550/s | 102 % | parity | server CPU/handshake 215 vs 219 µs |
| 9 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 434 µs | 448 µs | 103 % | parity |  |
| 10 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 70,026/s | 67,685/s | 103 % | parity | not TLS: the HTTP/1.1 server itself |
| 11 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 990 MB/s | 918 MB/s | 108 % | ahead | server CPU 971 vs 1,058 ns/KB; the AEAD alone is 496 vs 434 ns/KB |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 250 µs | 273 µs | 109 % | ahead |  |
| 13 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,598/s | 4,983/s | 112 % | ahead | server CPU/handshake 178 vs 200 µs |
| 14 | record layer | Keep-alive 1 KB over TLS — req/s | 61,950/s | 50,640/s | 122 % | ahead | TLS adds 1.80 µs CPU per request on NURL, 4.91 µs on Rust (TLS minus plaintext) |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,551/s | 1,266/s | 123 % | ahead | p50 645 vs 784 µs per request |
| 16 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 928 MB/s | 748 MB/s | 124 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,517/s | 1,161/s | 131 % | ahead | p50 659 vs 854 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 15,759/s | 11,357/s | 139 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,647 | 100 % | 215 | 64.8 | 150 | 7,315 / 8,939 | 375 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,550 | 100 % | 219 | 59.7 | 160 | 7,049 / 8,964 | 354 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,598 | 100 % | 178 | 44.3 | 134 | 5,988 / 7,064 | 250 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 4,983 | 100 % | 200 | 41.9 | 158 | 7,444 / 9,370 | 273 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,710 | 100 % | 269 | 116 | 153 | 9,185 / 11,509 | 434 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,819 | 100 % | 261 | 84.7 | 177 | 8,471 / 10,549 | 448 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,912 | 100 % | 255 | 83.9 | 171 | 8,684 / 10,571 | 450 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 3,965 | 100 % | 252 | 72.9 | 179 | 8,169 / 10,083 | 458 | — |
| Full · RSA-2048 · X25519 | NURL | 884 | 100 % | 1,128 | 924 | 204 | 37,519 / 55,175 | 1,243 | — |
| Full · RSA-2048 · X25519 | RUST | 1,147 | 100 % | 869 | 704 | 165 | 27,747 / 39,614 | 999 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 61,950 | 100 % | 16.1 | 1,030 / 1,167 | 1.80 |
| NURL | plaintext | 70,026 | 100 % | 14.3 | 916 / 991 |  |
| RUST | TLS | 50,640 | 100 % | 19.7 | 1,280 / 1,360 | 4.91 |
| RUST | plaintext | 67,685 | 100 % | 14.8 | 967 / 1,027 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,235 | 83 % | 686 | 139 | — |
| NURL | chacha | 990 | 94 % | 971 | 496 | — |
| NURL | plain | 4,827 | 92 % | 195 | n/a | — |
| NURL | aes128+ktls | 897 | 64 % | 733 | 139 | yes |
| RUST | aes128 | 1,391 | 92 % | 677 | 247 | — |
| RUST | chacha | 918 | 95 % | 1,058 | 434 | — |
| RUST | plain | 4,500 | 92 % | 208 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,517 | 0.02 | 659 / 708 | 0 |
| full:/ | reqwest | 1,161 | 0.02 | 854 / 901 | 0 |
| resume:/ | http-client | 1,551 | 0.02 | 645 / 698 | 0 |
| resume:/ | reqwest | 1,266 | 0.02 | 784 / 836 | 0 |
| ka:/1k | http-client | 15,759 | 16.1 | 61.0 / 94.0 | 0 |
| ka:/1k | reqwest | 11,357 | 11.6 | 83.0 / 120 | 0 |
| ka:/1m | http-client | 885 | 928 | 1,124 / 1,250 | 0 |
| ka:/1m | reqwest | 713 | 748 | 1,456 / 1,800 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 11.3 | 8.74 | 77 % |
| X25519 shared | 30.8 | 28.0 | 91 % |
| P-256 ECDH keygen | 16.2 | 10.3 | 63 % |
| P-256 ECDH shared | 77.4 | 51.5 | 66 % |
| ML-KEM-768 encaps | 19.1 | 13.3 | 69 % |
| ECDSA P-256 sign | 20.5 | 17.7 | 86 % |
| ECDSA P-256 verify | 87.8 | 58.0 | 66 % |
| RSA-2048 PSS sign | 880 | 662 | 75 % |
| HKDF-Expand-Label | 0.14 | 0.33 | 237 % |
| SHA-256 16 KB | 10.4 | 10.4 | 100 % |
| AES-128-GCM seal 16 KB | 2.22 | 3.95 | 178 % |
| ChaCha20-Poly1305 seal 16 KB | 7.93 | 6.95 | 88 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `afec0dd7900ab25b3f071a533ffcef70fabf2ca3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40660419401 |
| NURL | `v0.79.1-30-gafec0dd7` |
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
