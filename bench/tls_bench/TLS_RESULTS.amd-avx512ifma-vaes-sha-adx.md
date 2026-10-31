# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `amd-avx512ifma-vaes-sha-adx`

Generated `2026-10-31T11:45:01Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `AMD EPYC 9V45 96-Core Processor`, commit `19ba7c74e448`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/41197725904). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `amd-avx512ifma-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 254 µs | 204 µs | 80 % | behind |  |
| 2 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,098 MB/s | 1,350 MB/s | 81 % | behind | server CPU 899 vs 725 ns/KB; the AEAD alone is 466 vs 355 ns/KB |
| 3 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 212 µs | 177 µs | 83 % | behind |  |
| 4 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,813/s | 3,303/s | 85 % | behind | server CPU 355 vs 302 µs/handshake: of the 52.6 µs gap, 49.3 µs is primitive crypto (largest: RSA-2048 PSS sign, +46.5 µs), 3.35 µs is protocol / runtime / I/O |
| 5 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 405 µs | 347 µs | 86 % | behind |  |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 7,243/s | 7,764/s | 93 % | behind | server CPU 138 vs 129 µs/handshake: of the 9.35 µs gap, 5.19 µs is primitive crypto (largest: X25519 shared, +2.26 µs), 4.17 µs is protocol / runtime / I/O |
| 7 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 7,314/s | 7,771/s | 94 % | behind | server CPU 137 vs 129 µs/handshake: of the 8.03 µs gap, 12.2 µs is primitive crypto (largest: P-256 ECDH shared, +10.5 µs), NURL's protocol / runtime / I/O is 4.16 µs CHEAPER than Rust's |
| 8 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 119,820/s | 125,375/s | 96 % | parity | not TLS: the HTTP/1.1 server itself |
| 9 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 8,757/s | 9,038/s | 97 % | parity | server CPU 114 vs 111 µs/handshake: of the 3.47 µs gap, 3.41 µs is primitive crypto (largest: X25519 shared, +2.26 µs), 0.05 µs is protocol / runtime / I/O |
| 10 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 129 µs | 125 µs | 97 % | parity |  |
| 11 | record layer | Keep-alive 1 KB over TLS — req/s | 114,540/s | 112,989/s | 101 % | parity | TLS adds 0.37 µs CPU per request on NURL, 0.86 µs on Rust (TLS minus plaintext) |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 10,251/s | 10,068/s | 102 % | parity | server CPU/handshake 97.4 vs 99.1 µs |
| 13 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 233 µs | 244 µs | 105 % | parity |  |
| 14 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 3,244 MB/s | 2,960 MB/s | 110 % | ahead | server CPU 302 vs 330 ns/KB; the AEAD alone is 52.5 vs 40.3 ns/KB |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 2,395/s | 2,058/s | 116 % | ahead | p50 405 vs 481 µs per request |
| 16 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 36,688/s | 30,998/s | 118 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 2,352/s | 1,809/s | 130 % | ahead | p50 415 vs 535 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 2,611 MB/s | 1,864 MB/s | 140 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 8,757 | 100 % | 114 | 37.4 | 76.5 | 3,866 / 4,819 | 212 | — |
| Full · ECDSA P-256 · X25519 | RUST | 9,038 | 100 % | 111 | 34.0 | 76.5 | 3,888 / 5,580 | 177 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 10,251 | 100 % | 97.4 | 26.1 | 71.4 | 3,231 / 3,907 | 129 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 10,068 | 100 % | 99.1 | 23.3 | 75.9 | 3,817 / 5,145 | 125 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 7,314 | 100 % | 137 | 60.0 | 76.5 | 4,668 / 5,832 | 254 | — |
| Full · ECDSA P-256 · P-256 | RUST | 7,771 | 100 % | 129 | 47.8 | 80.7 | 4,156 / 6,066 | 204 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 7,243 | 100 % | 138 | 49.4 | 88.6 | 4,736 / 5,672 | 233 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 7,764 | 100 % | 129 | 44.2 | 84.4 | 4,685 / 6,532 | 244 | — |
| Full · RSA-2048 · X25519 | NURL | 2,813 | 100 % | 355 | 274 | 81.2 | 11,928 / 15,532 | 405 | — |
| Full · RSA-2048 · X25519 | RUST | 3,303 | 100 % | 302 | 225 | 77.8 | 11,597 / 17,570 | 347 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 114,540 | 100 % | 8.70 | 555 / 617 | 0.37 |
| NURL | plaintext | 119,820 | 100 % | 8.34 | 534 / 579 |  |
| RUST | TLS | 112,989 | 100 % | 8.83 | 564 / 861 | 0.86 |
| RUST | plaintext | 125,375 | 100 % | 7.97 | 516 / 582 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 3,244 | 96 % | 302 | 52.5 | — |
| NURL | chacha | 1,098 | 96 % | 899 | 466 | — |
| NURL | plain | 6,784 | 93 % | 140 | n/a | — |
| NURL | aes128+ktls | 1,607 | 76 % | 487 | 52.5 | yes |
| RUST | aes128 | 2,960 | 95 % | 330 | 40.3 | — |
| RUST | chacha | 1,350 | 96 % | 725 | 355 | — |
| RUST | plain | 6,950 | 91 % | 135 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 2,352 | 0.03 | 415 / 751 | 0 |
| full:/ | reqwest | 1,809 | 0.03 | 535 / 992 | 0 |
| resume:/ | http-client | 2,395 | 0.03 | 405 / 798 | 0 |
| resume:/ | reqwest | 2,058 | 0.03 | 481 / 532 | 0 |
| ka:/1k | http-client | 36,688 | 37.6 | 27.0 / 37.0 | 0 |
| ka:/1k | reqwest | 30,998 | 31.7 | 31.0 / 45.0 | 0 |
| ka:/1m | http-client | 2,490 | 2,611 | 400 / 505 | 0 |
| ka:/1m | reqwest | 1,778 | 1,864 | 471 / 851 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 6.83 | 4.80 | 70 % |
| X25519 shared | `adx` | 17.7 | 15.4 | 87 % |
| P-256 ECDH keygen | `adx` | 8.72 | 6.16 | 71 % |
| P-256 ECDH shared | `adx` | 38.4 | 27.9 | 73 % |
| ML-KEM-768 encaps | `avx2` | 12.0 | 10.2 | 85 % |
| ECDSA P-256 sign | `adx` | 11.4 | 10.8 | 95 % |
| ECDSA P-256 verify | `adx` | 40.7 | 32.9 | 81 % |
| RSA-2048 PSS sign | `ifma` | 248 | 201 | 81 % |
| HKDF-Expand-Label | `sha-ni` | 0.10 | 0.19 | 197 % |
| SHA-256 16 KB | `sha-ni` | 7.58 | 7.78 | 103 % |
| AES-128-GCM seal 16 KB | `vaes512` | 0.84 | 0.65 | 77 % |
| ChaCha20-Poly1305 seal 16 KB | `avx2` | 7.46 | 5.67 | 76 % |

## Environment

| Item | Value |
|---|---|
| CPU family | `amd-avx512ifma-vaes-sha-adx` (vendor and flags; see bench/tls_bench/README.md) |
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | `AMD EPYC 9V45 96-Core Processor` |
| CPU vendor | `AuthenticAMD` |
| CPU flags (the crypto-relevant ones present) | `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq gfni avx512f avx512vl avx512bw avx512ifma avx512vbmi` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `19ba7c74e448bad968f518f3b81c13cc39f98625` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41197725904 |
| NURL | `v0.82.0-33-g19ba7c74` |
| NURL_CPU_* masking | `none` |
| OPENSSL_ia32cap (aws-lc's CPUID mask) | `unset` |
| Rust | `rustc 1.99.1 (58cf8f9c3 2026-10-13)` |
| Cell durations (s) | `hs=15 lat=5 ka=10 client=6 prim_runs=3` |
| rustls | `0.23.46` |
| aws-lc-rs | `1.18.2` |
| hyper | `1.12.0` |
| tokio | `1.54.1` |
| reqwest | `0.12.28` |
| NURL CPU probes | `v3=1 aes=1 vaes=1 vaes512=1 sha=1 adx=1 ifma=1` |

### Reading these numbers

- **Read pairs, not cells.** Both servers ran on the same cores in the same run; a shared CI VM moves absolute numbers between runs by more than it moves the ratio.
- **A ratio belongs to its CPU family.** aws-lc and NURL each pick kernels by CPUID, so the same code can lead on one family and trail on another. Compare this report only with an earlier one of the same family; the index sets the families side by side.
- **CPU per operation is the absolute number.** Rates depend on how many cores the server had; server CPU per handshake / per request / per KB does not, and it is what the crypto budget is subtracted from.
- **The crypto budget is a floor, not a model.** It counts each primitive once at its single-core, warm-cache cost. *Rest* therefore also holds cache misses the microbenchmark does not see — a large *rest* with a small primitive gap points at the protocol code, the allocator or the I/O path.
- **The client rows include the library.** http-client and reqwest are measured as an application calls them (pooling, header handling, response assembly), not as bare TLS.
