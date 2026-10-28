# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-28T09:24:09Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 901/s | 1,162/s | 78 % | behind | server CPU 1,107 vs 859 µs/handshake: of the 249 µs gap, 222 µs is primitive crypto (largest: RSA-2048 PSS sign, +220 µs), 26.6 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,229 µs | 958 µs | 78 % | behind |  |
| 3 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,263 MB/s | 1,477 MB/s | 86 % | behind | server CPU 547 vs 641 ns/KB; the AEAD alone is 138 vs 248 ns/KB |
| 4 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 448 µs | 422 µs | 94 % | behind |  |
| 5 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,729/s | 3,855/s | 97 % | parity | server CPU 268 vs 259 µs/handshake: of the 8.79 µs gap, 31.5 µs is primitive crypto (largest: P-256 ECDH shared, +26.0 µs), NURL's protocol / runtime / I/O is 22.7 µs CHEAPER than Rust's |
| 6 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 375 µs | 374 µs | 100 % | parity |  |
| 7 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 282 µs | 283 µs | 100 % | parity |  |
| 8 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 69,847/s | 69,544/s | 100 % | parity | not TLS: the HTTP/1.1 server itself |
| 9 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 4,043/s | 4,014/s | 101 % | parity | server CPU/handshake 247 vs 249 µs |
| 10 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 433 µs | 444 µs | 103 % | parity |  |
| 11 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,743/s | 4,577/s | 104 % | parity | server CPU/handshake 210 vs 218 µs |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,686/s | 5,019/s | 113 % | ahead | server CPU/handshake 175 vs 199 µs |
| 13 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 926 MB/s | 802 MB/s | 116 % | ahead | server CPU 936 vs 1,215 ns/KB; the AEAD alone is 495 vs 433 ns/KB |
| 14 | record layer | Keep-alive 1 KB over TLS — req/s | 60,843/s | 52,249/s | 116 % | ahead | TLS adds 2.08 µs CPU per request on NURL, 4.70 µs on Rust (TLS minus plaintext) |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,574/s | 1,285/s | 123 % | ahead | p50 635 vs 772 µs per request |
| 16 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 874 MB/s | 677 MB/s | 129 % | ahead |  |
| 17 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 12,139/s | 9,366/s | 130 % | ahead |  |
| 18 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,523/s | 1,174/s | 130 % | ahead | p50 655 vs 841 µs per request |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,743 | 100 % | 210 | 64.8 | 145 | 7,168 / 8,629 | 375 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,577 | 100 % | 218 | 59.7 | 158 | 7,009 / 8,874 | 374 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,686 | 100 % | 175 | 44.3 | 131 | 5,886 / 6,996 | 282 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 5,019 | 100 % | 199 | 42.0 | 157 | 6,363 / 7,798 | 283 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,729 | 100 % | 268 | 116 | 151 | 9,166 / 11,390 | 433 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,855 | 100 % | 259 | 84.9 | 174 | 8,402 / 10,392 | 444 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 4,043 | 100 % | 247 | 84.0 | 163 | 8,436 / 10,260 | 448 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,014 | 100 % | 249 | 73.0 | 176 | 8,063 / 10,310 | 422 | — |
| Full · RSA-2048 · X25519 | NURL | 901 | 100 % | 1,107 | 925 | 182 | 37,193 / 53,422 | 1,229 | — |
| Full · RSA-2048 · X25519 | RUST | 1,162 | 100 % | 859 | 703 | 156 | 27,479 / 41,337 | 958 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 60,843 | 100 % | 16.4 | 1,049 / 1,147 | 2.08 |
| NURL | plaintext | 69,847 | 100 % | 14.3 | 917 / 1,001 |  |
| RUST | TLS | 52,249 | 100 % | 19.1 | 1,239 / 1,369 | 4.70 |
| RUST | plaintext | 69,544 | 100 % | 14.4 | 934 / 1,022 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,263 | 68 % | 547 | 138 | — |
| NURL | chacha | 926 | 85 % | 936 | 495 | — |
| NURL | plain | 3,910 | 90 % | 235 | n/a | — |
| NURL | aes128+ktls | 802 | 90 % | 1,151 | 138 | yes |
| RUST | aes128 | 1,477 | 92 % | 641 | 248 | — |
| RUST | chacha | 802 | 95 % | 1,215 | 433 | — |
| RUST | plain | 4,347 | 86 % | 202 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,523 | 0.02 | 655 / 722 | 0 |
| full:/ | reqwest | 1,174 | 0.02 | 841 / 901 | 0 |
| resume:/ | http-client | 1,574 | 0.02 | 635 / 696 | 0 |
| resume:/ | reqwest | 1,285 | 0.02 | 772 / 823 | 0 |
| ka:/1k | http-client | 12,139 | 12.4 | 81.0 / 95.0 | 0 |
| ka:/1k | reqwest | 9,366 | 9.59 | 105 / 120 | 0 |
| ka:/1m | http-client | 834 | 874 | 1,196 / 1,266 | 0 |
| ka:/1m | reqwest | 646 | 677 | 1,536 / 1,595 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 11.3 | 8.70 | 77 % |
| X25519 shared | 30.8 | 28.0 | 91 % |
| P-256 ECDH keygen | 16.1 | 10.3 | 64 % |
| P-256 ECDH shared | 77.5 | 51.6 | 67 % |
| ML-KEM-768 encaps | 19.1 | 13.3 | 70 % |
| ECDSA P-256 sign | 20.5 | 17.7 | 86 % |
| ECDSA P-256 verify | 87.9 | 57.9 | 66 % |
| RSA-2048 PSS sign | 881 | 661 | 75 % |
| HKDF-Expand-Label | 0.14 | 0.33 | 242 % |
| SHA-256 16 KB | 10.4 | 10.4 | 100 % |
| AES-128-GCM seal 16 KB | 2.21 | 3.96 | 179 % |
| ChaCha20-Poly1305 seal 16 KB | 7.92 | 6.92 | 87 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `78c07102d8485a5fcc1f6014364993d143250d17` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40663302750 |
| NURL | `v0.79.1-32-g78c07102` |
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
