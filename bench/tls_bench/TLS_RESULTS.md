# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-29T11:50:10Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 900/s | 1,152/s | 78 % | behind | server CPU 1,108 vs 866 µs/handshake: of the 242 µs gap, 230 µs is primitive crypto (largest: RSA-2048 PSS sign, +228 µs), 11.9 µs is protocol / runtime / I/O |
| 2 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 888 MB/s | 1,123 MB/s | 79 % | behind | server CPU 1,078 vs 856 ns/KB; the AEAD alone is 502 vs 434 ns/KB |
| 3 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,215 µs | 992 µs | 82 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,807/s | 3,891/s | 98 % | parity | server CPU 262 vs 256 µs/handshake: of the 5.52 µs gap, 25.9 µs is primitive crypto (largest: P-256 ECDH shared, +20.8 µs), NURL's protocol / runtime / I/O is 20.4 µs CHEAPER than Rust's |
| 5 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 444 µs | 439 µs | 99 % | parity |  |
| 6 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 75,311/s | 75,570/s | 100 % | parity | not TLS: the HTTP/1.1 server itself |
| 7 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 4,022/s | 4,033/s | 100 % | parity | server CPU 248 vs 247 µs/handshake: of the 0.66 µs gap, 10.4 µs is primitive crypto (largest: ML-KEM-768 encaps, +5.66 µs), NURL's protocol / runtime / I/O is 9.78 µs CHEAPER than Rust's |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 416 µs | 419 µs | 101 % | parity |  |
| 9 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,697/s | 4,613/s | 102 % | parity | server CPU/handshake 212 vs 216 µs |
| 10 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 339 µs | 354 µs | 104 % | parity |  |
| 11 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,504 MB/s | 1,372 MB/s | 110 % | ahead | server CPU 566 vs 653 ns/KB; the AEAD alone is 138 vs 247 ns/KB |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,611/s | 5,094/s | 110 % | ahead | server CPU/handshake 178 vs 196 µs |
| 13 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 256 µs | 296 µs | 116 % | ahead |  |
| 14 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,606/s | 1,304/s | 123 % | ahead | p50 624 vs 762 µs per request |
| 15 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 963 MB/s | 776 MB/s | 124 % | ahead |  |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,571/s | 1,197/s | 131 % | ahead | p50 638 vs 830 µs per request |
| 17 | record layer | Keep-alive 1 KB over TLS — req/s | 67,643/s | 51,221/s | 132 % | ahead | TLS adds 1.45 µs CPU per request on NURL, 6.21 µs on Rust (TLS minus plaintext) |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 16,987/s | 11,874/s | 143 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,697 | 100 % | 212 | 64.6 | 148 | 7,242 / 9,114 | 339 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,613 | 100 % | 216 | 59.8 | 156 | 7,792 / 10,815 | 354 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,611 | 100 % | 178 | 44.3 | 133 | 5,968 / 7,108 | 256 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 5,094 | 100 % | 196 | 42.1 | 154 | 6,284 / 7,662 | 296 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,807 | 100 % | 262 | 111 | 151 | 8,989 / 11,125 | 444 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,891 | 100 % | 256 | 84.8 | 172 | 8,298 / 10,441 | 439 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 4,022 | 100 % | 248 | 83.6 | 165 | 8,445 / 10,299 | 416 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,033 | 100 % | 247 | 73.2 | 174 | 7,987 / 10,083 | 419 | — |
| Full · RSA-2048 · X25519 | NURL | 900 | 100 % | 1,108 | 934 | 174 | 37,363 / 52,313 | 1,215 | — |
| Full · RSA-2048 · X25519 | RUST | 1,152 | 100 % | 866 | 704 | 162 | 27,777 / 37,480 | 992 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 67,643 | 100 % | 14.7 | 945 / 1,050 | 1.45 |
| NURL | plaintext | 75,311 | 100 % | 13.3 | 873 / 945 |  |
| RUST | TLS | 51,221 | 100 % | 19.4 | 1,290 / 1,373 | 6.21 |
| RUST | plaintext | 75,570 | 100 % | 13.2 | 863 / 969 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,504 | 83 % | 566 | 138 | — |
| NURL | chacha | 888 | 94 % | 1,078 | 502 | — |
| NURL | plain | 3,691 | 93 % | 259 | n/a | — |
| NURL | aes128+ktls | 994 | 80 % | 819 | 138 | yes |
| RUST | aes128 | 1,372 | 88 % | 653 | 247 | — |
| RUST | chacha | 1,123 | 94 % | 856 | 434 | — |
| RUST | plain | 4,079 | 92 % | 231 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,571 | 0.02 | 638 / 681 | 0 |
| full:/ | reqwest | 1,197 | 0.02 | 830 / 865 | 0 |
| resume:/ | http-client | 1,606 | 0.02 | 624 / 667 | 0 |
| resume:/ | reqwest | 1,304 | 0.02 | 762 / 800 | 0 |
| ka:/1k | http-client | 16,987 | 17.4 | 56.0 / 87.0 | 0 |
| ka:/1k | reqwest | 11,874 | 12.2 | 80.0 / 112 | 0 |
| ka:/1m | http-client | 919 | 963 | 1,083 / 1,217 | 0 |
| ka:/1m | reqwest | 740 | 776 | 1,336 / 1,750 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 11.3 | 8.74 | 77 % |
| X25519 shared | 30.8 | 28.0 | 91 % |
| P-256 ECDH keygen | 16.0 | 10.3 | 64 % |
| P-256 ECDH shared | 72.2 | 51.5 | 71 % |
| ML-KEM-768 encaps | 19.0 | 13.3 | 70 % |
| ECDSA P-256 sign | 20.3 | 17.8 | 88 % |
| ECDSA P-256 verify | 82.9 | 57.7 | 70 % |
| RSA-2048 PSS sign | 890 | 662 | 74 % |
| HKDF-Expand-Label | 0.14 | 0.33 | 243 % |
| SHA-256 16 KB | 10.4 | 10.4 | 99 % |
| AES-128-GCM seal 16 KB | 2.22 | 3.95 | 178 % |
| ChaCha20-Poly1305 seal 16 KB | 8.03 | 6.94 | 86 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `29401773a39338856856756f52c5846acaa6b496` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40867838911 |
| NURL | `v0.80.0-54-g29401773` |
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
