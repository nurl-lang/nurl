# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `intel-avx512ifma-vaes-sha-adx`

Generated `2026-11-19T09:57:07Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `Intel(R) Xeon(R) 6975P-C`, commit `e15ed57f998c`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/44499500298). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `intel-avx512ifma-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 144 µs | 126 µs | 88 % | behind |  |
| 2 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,502/s | 2,831/s | 88 % | behind | server CPU 399 vs 353 µs/handshake: of the 46.6 µs gap, 46.1 µs is primitive crypto (largest: RSA-2048 PSS sign, +45.2 µs), 0.50 µs is protocol / runtime / I/O |
| 3 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 449 µs | 399 µs | 89 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 261 µs | 242 µs | 93 % | behind |  |
| 5 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 7,206/s | 7,464/s | 97 % | parity | server CPU 139 vs 134 µs/handshake: of the 4.98 µs gap, 3.71 µs is primitive crypto (largest: ML-KEM-768 encaps, +2.22 µs), 1.27 µs is protocol / runtime / I/O |
| 6 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 6,762/s | 6,957/s | 97 % | parity | server CPU 148 vs 144 µs/handshake: of the 4.14 µs gap, 8.92 µs is primitive crypto (largest: P-256 ECDH shared, +7.51 µs), NURL's protocol / runtime / I/O is 4.78 µs CHEAPER than Rust's |
| 7 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 172,953/s | 173,732/s | 100 % | parity | not TLS: the HTTP/1.1 server itself |
| 8 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 197 µs | 197 µs | 100 % | parity |  |
| 9 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 261 µs | 264 µs | 101 % | parity |  |
| 10 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 3,335 MB/s | 3,296 MB/s | 101 % | parity | server CPU 289 vs 285 ns/KB; the AEAD alone is 53.9 vs 54.8 ns/KB |
| 11 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 8,868/s | 8,692/s | 102 % | parity | server CPU/handshake 113 vs 115 µs |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 11,503/s | 11,040/s | 104 % | parity | server CPU/handshake 86.8 vs 90.4 µs |
| 13 | record layer | Keep-alive 1 KB over TLS — req/s | 150,893/s | 143,979/s | 105 % | parity | TLS adds 0.83 µs CPU per request on NURL, 1.17 µs on Rust (TLS minus plaintext) |
| 14 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 27,243/s | 24,354/s | 112 % | ahead |  |
| 15 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,443 MB/s | 1,214 MB/s | 119 % | ahead | server CPU 495 vs 801 ns/KB; the AEAD alone is 272 vs 420 ns/KB |
| 16 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 3,159 MB/s | 2,649 MB/s | 119 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 3,580/s | 2,837/s | 126 % | ahead | p50 273 vs 347 µs per request |
| 18 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 3,447/s | 2,359/s | 146 % | ahead | p50 284 vs 419 µs per request |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 8,868 | 100 % | 113 | 46.6 | 66.0 | 3,876 / 4,812 | 197 | — |
| Full · ECDSA P-256 · X25519 | RUST | 8,692 | 100 % | 115 | 45.1 | 69.7 | 3,843 / 5,760 | 197 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 11,503 | 100 % | 86.8 | 31.0 | 55.8 | 2,917 / 3,529 | 144 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 11,040 | 100 % | 90.4 | 30.1 | 60.3 | 3,434 / 5,071 | 126 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 6,762 | 100 % | 148 | 74.3 | 73.4 | 5,108 / 6,299 | 261 | — |
| Full · ECDSA P-256 · P-256 | RUST | 6,957 | 100 % | 144 | 65.4 | 78.2 | 4,748 / 7,098 | 242 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 7,206 | 100 % | 139 | 59.3 | 79.4 | 4,751 / 5,964 | 261 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 7,464 | 100 % | 134 | 55.6 | 78.1 | 4,584 / 6,940 | 264 | — |
| Full · RSA-2048 · X25519 | NURL | 2,502 | 100 % | 399 | 330 | 69.4 | 13,414 / 18,506 | 449 | — |
| Full · RSA-2048 · X25519 | RUST | 2,831 | 100 % | 353 | 284 | 68.9 | 11,112 / 19,206 | 399 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 150,893 | 100 % | 6.61 | 421 / 498 | 0.83 |
| NURL | plaintext | 172,953 | 100 % | 5.78 | 368 / 442 |  |
| RUST | TLS | 143,979 | 100 % | 6.92 | 449 / 526 | 1.17 |
| RUST | plaintext | 173,732 | 100 % | 5.75 | 372 / 446 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 3,335 | 94 % | 289 | 53.9 | — |
| NURL | chacha | 1,443 | 70 % | 495 | 272 | — |
| NURL | plain | 6,282 | 96 % | 156 | n/a | — |
| NURL | aes128+ktls | 1,681 | 53 % | 325 | 53.9 | yes |
| RUST | aes128 | 3,296 | 92 % | 285 | 54.8 | — |
| RUST | chacha | 1,214 | 95 % | 801 | 420 | — |
| RUST | plain | 5,013 | 74 % | 152 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 3,447 | 0.05 | 284 / 344 | 0 |
| full:/ | reqwest | 2,359 | 0.03 | 419 / 471 | 0 |
| resume:/ | http-client | 3,580 | 0.05 | 273 / 330 | 0 |
| resume:/ | reqwest | 2,837 | 0.04 | 347 / 410 | 0 |
| ka:/1k | http-client | 27,243 | 27.9 | 35.0 / 49.0 | 0 |
| ka:/1k | reqwest | 24,354 | 24.9 | 39.0 / 55.0 | 0 |
| ka:/1m | http-client | 3,013 | 3,159 | 329 / 373 | 0 |
| ka:/1m | reqwest | 2,526 | 2,649 | 388 / 558 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 7.23 | 6.76 | 94 % |
| X25519 shared | `adx` | 21.9 | 19.8 | 91 % |
| P-256 ECDH keygen | `adx` | 11.5 | 9.06 | 79 % |
| P-256 ECDH shared | `adx` | 45.3 | 37.8 | 83 % |
| ML-KEM-768 encaps | `avx2` | 12.7 | 10.4 | 82 % |
| ECDSA P-256 sign | `adx` | 15.6 | 15.0 | 96 % |
| ECDSA P-256 verify | `adx` | 49.2 | 50.1 | 102 % |
| RSA-2048 PSS sign | `ifma` | 299 | 254 | 85 % |
| HKDF-Expand-Label | `sha-ni` | 0.12 | 0.22 | 189 % |
| SHA-256 16 KB | `sha-ni` | 8.81 | 8.79 | 100 % |
| AES-128-GCM seal 16 KB | `vaes512` | 0.86 | 0.88 | 102 % |
| ChaCha20-Poly1305 seal 16 KB | `avx512` | 4.36 | 6.72 | 154 % |

## Environment

| Item | Value |
|---|---|
| CPU family | `intel-avx512ifma-vaes-sha-adx` (vendor and flags; see bench/tls_bench/README.md) |
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1016-aws x86_64` |
| CPU | `Intel(R) Xeon(R) 6975P-C` |
| CPU vendor | `GenuineIntel` |
| CPU flags (the crypto-relevant ones present) | `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq gfni avx512f avx512vl avx512bw avx512ifma avx512vbmi` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `e15ed57f998cbc8deb360fef791281fe77b5e588` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/44499500298 |
| NURL | `v0.92.1-82-ge15ed57f` |
| NURL_CPU_* masking | `none` |
| OPENSSL_ia32cap (aws-lc's CPUID mask) | `unset` |
| Rust | `rustc 1.100.0 (0ef1bc386 2026-11-09)` |
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
