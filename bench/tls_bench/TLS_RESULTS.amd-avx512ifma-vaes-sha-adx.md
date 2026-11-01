# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `amd-avx512ifma-vaes-sha-adx`

Generated `2026-11-01T18:08:41Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `AMD EPYC 9V45 96-Core Processor`, commit `8b035c6f338e`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/41334756669). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `amd-avx512ifma-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,671/s | 3,271/s | 82 % | behind | server CPU 374 vs 305 µs/handshake: of the 68.3 µs gap, 52.2 µs is primitive crypto (largest: RSA-2048 PSS sign, +50.6 µs), 16.0 µs is protocol / runtime / I/O |
| 2 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 143 µs | 122 µs | 85 % | behind |  |
| 3 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 439 µs | 388 µs | 88 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 220 µs | 202 µs | 92 % | behind |  |
| 5 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 7,167/s | 7,678/s | 93 % | behind | server CPU 139 vs 130 µs/handshake: of the 9.27 µs gap, 4.40 µs is primitive crypto (largest: ML-KEM-768 encaps, +2.29 µs), 4.87 µs is protocol / runtime / I/O |
| 6 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 120,163/s | 125,529/s | 96 % | parity | not TLS: the HTTP/1.1 server itself |
| 7 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 7,178/s | 7,493/s | 96 % | parity | server CPU 139 vs 133 µs/handshake: of the 6.37 µs gap, 6.42 µs is primitive crypto (largest: P-256 ECDH shared, +5.76 µs), NURL's protocol / runtime / I/O is 0.04 µs CHEAPER than Rust's |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 229 µs | 223 µs | 97 % | parity |  |
| 9 | record layer | Keep-alive 1 KB over TLS — req/s | 111,805/s | 114,680/s | 97 % | parity | TLS adds 0.60 µs CPU per request on NURL, 0.74 µs on Rust (TLS minus plaintext) |
| 10 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 8,564/s | 8,726/s | 98 % | parity | server CPU 117 vs 114 µs/handshake: of the 2.08 µs gap, 2.11 µs is primitive crypto (largest: X25519 shared, +1.98 µs), NURL's protocol / runtime / I/O is 0.03 µs CHEAPER than Rust's |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 10,155/s | 9,806/s | 104 % | parity | server CPU/handshake 98.3 vs 102 µs |
| 12 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 2,700 MB/s | 2,572 MB/s | 105 % | parity |  |
| 13 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,537 MB/s | 1,380 MB/s | 111 % | ahead | server CPU 500 vs 706 ns/KB; the AEAD alone is 219 vs 373 ns/KB |
| 14 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 210 µs | 239 µs | 114 % | ahead |  |
| 15 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 35,385/s | 30,403/s | 116 % | ahead |  |
| 16 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 2,343/s | 2,000/s | 117 % | ahead | p50 417 vs 494 µs per request |
| 17 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 3,368 MB/s | 2,756 MB/s | 122 % | ahead | server CPU 290 vs 354 ns/KB; the AEAD alone is 52.1 vs 43.3 ns/KB |
| 18 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 2,308/s | 1,786/s | 129 % | ahead | p50 425 vs 546 µs per request |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 8,564 | 100 % | 117 | 37.6 | 78.9 | 3,961 / 4,824 | 220 | — |
| Full · ECDSA P-256 · X25519 | RUST | 8,726 | 100 % | 114 | 35.5 | 78.9 | 4,249 / 5,503 | 202 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 10,155 | 100 % | 98.3 | 26.0 | 72.3 | 3,264 / 3,901 | 143 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 9,806 | 100 % | 102 | 24.3 | 77.6 | 3,904 / 5,223 | 122 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 7,178 | 100 % | 139 | 56.7 | 82.5 | 4,764 / 5,788 | 210 | — |
| Full · ECDSA P-256 · P-256 | RUST | 7,493 | 100 % | 133 | 50.3 | 82.5 | 5,125 / 7,033 | 239 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 7,167 | 100 % | 139 | 48.7 | 90.7 | 4,759 / 5,836 | 229 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 7,678 | 100 % | 130 | 44.3 | 85.8 | 4,954 / 6,742 | 223 | — |
| Full · RSA-2048 · X25519 | NURL | 2,671 | 100 % | 374 | 284 | 89.5 | 12,495 / 18,355 | 439 | — |
| Full · RSA-2048 · X25519 | RUST | 3,271 | 100 % | 305 | 232 | 73.4 | 9,562 / 16,683 | 388 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 111,805 | 100 % | 8.93 | 568 / 667 | 0.60 |
| NURL | plaintext | 120,163 | 100 % | 8.32 | 533 / 613 |  |
| RUST | TLS | 114,680 | 100 % | 8.70 | 561 / 630 | 0.74 |
| RUST | plaintext | 125,529 | 100 % | 7.96 | 519 / 558 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 3,368 | 96 % | 290 | 52.1 | — |
| NURL | chacha | 1,537 | 75 % | 500 | 219 | — |
| NURL | plain | 7,242 | 93 % | 131 | n/a | — |
| NURL | aes128+ktls | 1,589 | 78 % | 505 | 52.1 | yes |
| RUST | aes128 | 2,756 | 95 % | 354 | 43.3 | — |
| RUST | chacha | 1,380 | 95 % | 706 | 373 | — |
| RUST | plain | 6,717 | 92 % | 141 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 2,308 | 0.03 | 425 / 613 | 0 |
| full:/ | reqwest | 1,786 | 0.03 | 546 / 897 | 0 |
| resume:/ | http-client | 2,343 | 0.03 | 417 / 694 | 0 |
| resume:/ | reqwest | 2,000 | 0.03 | 494 / 551 | 0 |
| ka:/1k | http-client | 35,385 | 36.2 | 27.0 / 39.0 | 0 |
| ka:/1k | reqwest | 30,403 | 31.1 | 32.0 / 44.0 | 0 |
| ka:/1m | http-client | 2,575 | 2,700 | 388 / 421 | 0 |
| ka:/1m | reqwest | 2,453 | 2,572 | 403 / 448 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 6.16 | 5.00 | 81 % |
| X25519 shared | `adx` | 18.2 | 16.2 | 89 % |
| P-256 ECDH keygen | `adx` | 8.12 | 6.42 | 79 % |
| P-256 ECDH shared | `adx` | 35.3 | 29.6 | 84 % |
| ML-KEM-768 encaps | `avx2` | 11.1 | 8.77 | 79 % |
| ECDSA P-256 sign | `adx` | 11.7 | 11.2 | 96 % |
| ECDSA P-256 verify | `adx` | 39.3 | 34.4 | 88 % |
| RSA-2048 PSS sign | `ifma` | 258 | 208 | 80 % |
| HKDF-Expand-Label | `sha-ni` | 0.10 | 0.19 | 189 % |
| SHA-256 16 KB | `sha-ni` | 7.85 | 7.89 | 100 % |
| AES-128-GCM seal 16 KB | `vaes512` | 0.83 | 0.69 | 83 % |
| ChaCha20-Poly1305 seal 16 KB | `avx512` | 3.51 | 5.97 | 170 % |

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
| Commit | `8b035c6f338e73fe57e833690deac07e046b9e3e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41334756669 |
| NURL | `v0.83.0-55-g8b035c6f` |
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
