# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-23T22:55:41Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 558/s | 1,135/s | 49 % | **gap** | server CPU 1,789 vs 878 µs/handshake: of the 911 µs gap, 887 µs is primitive crypto (largest: RSA-2048 PSS sign, +865 µs), 24.1 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,862 µs | 962 µs | 52 % | **gap** |  |
| 3 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 674 MB/s | 1,109 MB/s | 61 % | **gap** | server CPU 1,456 vs 831 ns/KB; the AEAD alone is 696 vs 434 ns/KB |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 2,625/s | 3,792/s | 69 % | **gap** | server CPU 380 vs 263 µs/handshake: of the 117 µs gap, 121 µs is primitive crypto (largest: P-256 ECDH shared, +63.4 µs), NURL's protocol / runtime / I/O is 4.25 µs CHEAPER than Rust's |
| 5 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,087/s | 3,968/s | 78 % | behind | server CPU 323 vs 251 µs/handshake: of the 71.7 µs gap, 68.1 µs is primitive crypto (largest: ECDSA P-256 sign, +32.6 µs), 3.55 µs is protocol / runtime / I/O |
| 6 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 522 µs | 413 µs | 79 % | behind |  |
| 7 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 3,602/s | 4,397/s | 82 % | behind | server CPU 277 vs 227 µs/handshake: of the 50.1 µs gap, 54.1 µs is primitive crypto (largest: ECDSA P-256 sign, +32.6 µs), NURL's protocol / runtime / I/O is 4.02 µs CHEAPER than Rust's |
| 8 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 433 µs | 359 µs | 83 % | behind |  |
| 9 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 305 µs | 281 µs | 92 % | behind |  |
| 10 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 479 µs | 443 µs | 92 % | behind |  |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 4,794/s | 4,848/s | 99 % | parity | server CPU 208 vs 206 µs/handshake: of the 2.44 µs gap, 21.5 µs is primitive crypto (largest: X25519 shared, +17.8 µs), NURL's protocol / runtime / I/O is 19.0 µs CHEAPER than Rust's |
| 12 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 70,320/s | 69,120/s | 102 % | parity | not TLS: the HTTP/1.1 server itself |
| 13 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,403/s | 1,251/s | 112 % | ahead | p50 708 vs 787 µs per request |
| 14 | record layer | Keep-alive 1 KB over TLS — req/s | 60,486/s | 52,198/s | 116 % | ahead | TLS adds 2.25 µs CPU per request on NURL, 4.65 µs on Rust (TLS minus plaintext) |
| 15 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 878 MB/s | 738 MB/s | 119 % | ahead |  |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,377/s | 1,151/s | 120 % | ahead | p50 722 vs 857 µs per request |
| 17 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,601 MB/s | 1,251 MB/s | 128 % | ahead | server CPU 500 vs 759 ns/KB; the AEAD alone is 138 vs 247 ns/KB |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 12,080/s | 9,178/s | 132 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 3,602 | 100 % | 277 | 114 | 163 | 7,728 / 15,245 | 433 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,397 | 100 % | 227 | 59.8 | 167 | 8,405 / 10,757 | 359 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 4,794 | 100 % | 208 | 63.7 | 144 | 6,228 / 9,948 | 305 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 4,848 | 100 % | 206 | 42.2 | 164 | 6,588 / 8,035 | 281 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 2,625 | 100 % | 380 | 206 | 174 | 4,586 / 21,401 | 522 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,792 | 100 % | 263 | 84.8 | 178 | 8,519 / 10,671 | 413 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,087 | 100 % | 323 | 142 | 181 | 3,960 / 17,224 | 479 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 3,968 | 100 % | 251 | 73.6 | 178 | 8,166 / 10,297 | 443 | — |
| Full · RSA-2048 · X25519 | NURL | 558 | 100 % | 1,789 | 1,591 | 197 | 54,121 / 106,621 | 1,862 | — |
| Full · RSA-2048 · X25519 | RUST | 1,135 | 100 % | 878 | 704 | 173 | 28,041 / 39,812 | 962 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 60,486 | 100 % | 16.5 | 1,098 / 1,267 | 2.25 |
| NURL | plaintext | 70,320 | 100 % | 14.2 | 943 / 1,070 |  |
| RUST | TLS | 52,198 | 100 % | 19.1 | 1,241 / 1,377 | 4.65 |
| RUST | plaintext | 69,120 | 100 % | 14.5 | 940 / 1,035 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,601 | 78 % | 500 | 138 | — |
| NURL | chacha | 674 | 96 % | 1,456 | 696 | — |
| NURL | plain | 4,019 | 90 % | 228 | n/a | — |
| NURL | aes128+ktls | 779 | 60 % | 786 | 138 | yes |
| RUST | aes128 | 1,251 | 93 % | 759 | 247 | — |
| RUST | chacha | 1,109 | 90 % | 831 | 434 | — |
| RUST | plain | 4,166 | 85 % | 209 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,377 | 0.02 | 722 / 806 | 0 |
| full:/ | reqwest | 1,151 | 0.02 | 857 / 952 | 0 |
| resume:/ | http-client | 1,403 | 0.02 | 708 / 798 | 0 |
| resume:/ | reqwest | 1,251 | 0.02 | 787 / 898 | 0 |
| ka:/1k | http-client | 12,080 | 12.4 | 82.0 / 97.0 | 0 |
| ka:/1k | reqwest | 9,178 | 9.40 | 106 / 131 | 0 |
| ka:/1m | http-client | 837 | 878 | 1,186 / 1,285 | 0 |
| ka:/1m | reqwest | 704 | 738 | 1,378 / 2,008 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 15.6 | 8.69 | 56 % |
| X25519 shared | 45.8 | 28.0 | 61 % |
| P-256 ECDH keygen | 38.8 | 10.3 | 26 % |
| P-256 ECDH shared | 115 | 51.4 | 45 % |
| ML-KEM-768 encaps | 27.8 | 13.7 | 50 % |
| ECDSA P-256 sign | 50.3 | 17.6 | 35 % |
| ECDSA P-256 verify | 137 | 57.9 | 42 % |
| RSA-2048 PSS sign | 1,527 | 662 | 43 % |
| HKDF-Expand-Label | 0.14 | 0.34 | 243 % |
| SHA-256 16 KB | 10.4 | 10.3 | 100 % |
| AES-128-GCM seal 16 KB | 2.21 | 3.95 | 179 % |
| ChaCha20-Poly1305 seal 16 KB | 11.1 | 6.95 | 62 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `0f0dd4c787ab7bdcd88de9bb4c5b0e8e17d70e0d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40035625396 |
| NURL | `v0.77.2-25-g0f0dd4c7` |
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
