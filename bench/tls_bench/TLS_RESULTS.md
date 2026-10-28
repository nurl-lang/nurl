# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-28T09:12:33Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 816/s | 1,060/s | 77 % | behind | server CPU 1,223 vs 941 µs/handshake: of the 282 µs gap, 254 µs is primitive crypto (largest: RSA-2048 PSS sign, +251 µs), 28.2 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,301 µs | 1,039 µs | 80 % | behind |  |
| 3 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,732/s | 4,007/s | 93 % | behind | server CPU 267 vs 249 µs/handshake: of the 18.3 µs gap, 37.0 µs is primitive crypto (largest: P-256 ECDH shared, +30.2 µs), NURL's protocol / runtime / I/O is 18.7 µs CHEAPER than Rust's |
| 4 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 381 µs | 364 µs | 96 % | parity |  |
| 5 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 442 µs | 436 µs | 99 % | parity |  |
| 6 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 76,535/s | 77,425/s | 99 % | parity | not TLS: the HTTP/1.1 server itself |
| 7 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 4,075/s | 4,109/s | 99 % | parity | server CPU 245 vs 243 µs/handshake: of the 2.01 µs gap, 10.5 µs is primitive crypto (largest: ML-KEM-768 encaps, +4.40 µs), NURL's protocol / runtime / I/O is 8.51 µs CHEAPER than Rust's |
| 8 | record layer | Keep-alive 1 KB over TLS — req/s | 67,925/s | 67,617/s | 100 % | parity | TLS adds 1.60 µs CPU per request on NURL, 1.81 µs on Rust (TLS minus plaintext) |
| 9 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,832/s | 4,773/s | 101 % | parity | server CPU/handshake 206 vs 209 µs |
| 10 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 440 µs | 456 µs | 104 % | parity |  |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 245 µs | 255 µs | 104 % | parity |  |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,884/s | 5,310/s | 111 % | ahead | server CPU/handshake 169 vs 188 µs |
| 13 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 939 MB/s | 836 MB/s | 112 % | ahead |  |
| 14 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 865 MB/s | 762 MB/s | 114 % | ahead | server CPU 1,119 vs 1,154 ns/KB; the AEAD alone is 587 vs 499 ns/KB |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,523/s | 1,234/s | 123 % | ahead | p50 645 vs 798 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,504/s | 1,131/s | 133 % | ahead | p50 662 vs 875 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 18,973/s | 14,010/s | 135 % | ahead |  |
| 18 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,465 MB/s | 939 MB/s | 156 % | ahead | server CPU 540 vs 920 ns/KB; the AEAD alone is 146 vs 276 ns/KB |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,832 | 100 % | 206 | 72.2 | 134 | 7,037 / 8,735 | 381 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,773 | 100 % | 209 | 66.1 | 143 | 6,767 / 9,243 | 364 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,884 | 100 % | 169 | 49.5 | 120 | 5,652 / 6,824 | 245 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 5,310 | 100 % | 188 | 46.4 | 141 | 6,001 / 7,755 | 255 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,732 | 100 % | 267 | 131 | 137 | 9,128 / 11,448 | 440 | — |
| Full · ECDSA P-256 · P-256 | RUST | 4,007 | 100 % | 249 | 93.6 | 156 | 9,293 / 11,833 | 456 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 4,075 | 100 % | 245 | 92.6 | 152 | 8,336 / 10,298 | 442 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,109 | 100 % | 243 | 82.1 | 161 | 7,906 / 10,585 | 436 | — |
| Full · RSA-2048 · X25519 | NURL | 816 | 100 % | 1,223 | 1,043 | 180 | 40,922 / 61,539 | 1,301 | — |
| Full · RSA-2048 · X25519 | RUST | 1,060 | 100 % | 941 | 789 | 152 | 30,024 / 46,759 | 1,039 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 67,925 | 100 % | 14.7 | 937 / 1,013 | 1.60 |
| NURL | plaintext | 76,535 | 100 % | 13.1 | 836 / 940 |  |
| RUST | TLS | 67,617 | 100 % | 14.7 | 954 / 1,042 | 1.81 |
| RUST | plaintext | 77,425 | 100 % | 12.9 | 838 / 925 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,465 | 77 % | 540 | 146 | — |
| NURL | chacha | 865 | 95 % | 1,119 | 587 | — |
| NURL | plain | 3,615 | 92 % | 259 | n/a | — |
| NURL | aes128+ktls | 700 | 59 % | 868 | 146 | yes |
| RUST | aes128 | 939 | 84 % | 920 | 276 | — |
| RUST | chacha | 762 | 86 % | 1,154 | 499 | — |
| RUST | plain | 3,698 | 86 % | 238 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,504 | 0.02 | 662 / 730 | 0 |
| full:/ | reqwest | 1,131 | 0.02 | 875 / 932 | 0 |
| resume:/ | http-client | 1,523 | 0.02 | 645 / 1,042 | 0 |
| resume:/ | reqwest | 1,234 | 0.02 | 798 / 950 | 0 |
| ka:/1k | http-client | 18,973 | 19.4 | 51.0 / 69.0 | 0 |
| ka:/1k | reqwest | 14,010 | 14.3 | 68.0 / 90.0 | 0 |
| ka:/1m | http-client | 895 | 939 | 1,113 / 1,258 | 0 |
| ka:/1m | reqwest | 797 | 836 | 1,233 / 1,560 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 12.5 | 9.87 | 79 % |
| X25519 shared | 34.6 | 31.2 | 90 % |
| P-256 ECDH keygen | 18.2 | 11.5 | 63 % |
| P-256 ECDH shared | 87.3 | 57.0 | 65 % |
| ML-KEM-768 encaps | 20.4 | 16.0 | 78 % |
| ECDSA P-256 sign | 22.7 | 19.6 | 87 % |
| ECDSA P-256 verify | 99.8 | 64.4 | 65 % |
| RSA-2048 PSS sign | 993 | 742 | 75 % |
| HKDF-Expand-Label | 0.15 | 0.34 | 224 % |
| SHA-256 16 KB | 11.8 | 11.7 | 99 % |
| AES-128-GCM seal 16 KB | 2.34 | 4.41 | 189 % |
| ChaCha20-Poly1305 seal 16 KB | 9.39 | 7.98 | 85 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 9V74 80-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `8fb1ebced81f5d2d0ee11f669da1426a37b7773e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40661844942 |
| NURL | `v0.79.1-31-g8fb1ebce` |
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
