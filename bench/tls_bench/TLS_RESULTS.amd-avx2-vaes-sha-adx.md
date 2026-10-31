# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `amd-avx2-vaes-sha-adx`

Generated `2026-10-31T08:41:14Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `AMD EPYC 7763 64-Core Processor`, commit `1b258243b084`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/41185082810). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `amd-avx2-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,103 µs | 958 µs | 87 % | behind |  |
| 2 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 1,018/s | 1,154/s | 88 % | behind | server CPU 980 vs 864 µs/handshake: of the 115 µs gap, 112 µs is primitive crypto (largest: RSA-2048 PSS sign, +109 µs), 3.62 µs is protocol / runtime / I/O |
| 3 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 284 µs | 264 µs | 93 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,787/s | 3,923/s | 97 % | parity | server CPU 264 vs 254 µs/handshake: of the 9.11 µs gap, 24.1 µs is primitive crypto (largest: P-256 ECDH shared, +18.7 µs), NURL's protocol / runtime / I/O is 15.0 µs CHEAPER than Rust's |
| 5 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 442 µs | 429 µs | 97 % | parity |  |
| 6 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 454 µs | 443 µs | 98 % | parity |  |
| 7 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 377 µs | 369 µs | 98 % | parity |  |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 4,017/s | 4,019/s | 100 % | parity | server CPU 248 vs 248 µs/handshake: of the 0.17 µs gap, 10.6 µs is primitive crypto (largest: ML-KEM-768 encaps, +5.57 µs), NURL's protocol / runtime / I/O is 10.4 µs CHEAPER than Rust's |
| 9 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,671/s | 4,613/s | 101 % | parity | server CPU/handshake 214 vs 216 µs |
| 10 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 68,932/s | 66,014/s | 104 % | parity | not TLS: the HTTP/1.1 server itself |
| 11 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 961 MB/s | 914 MB/s | 105 % | ahead | server CPU 1,012 vs 1,055 ns/KB; the AEAD alone is 500 vs 434 ns/KB |
| 12 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 946 MB/s | 867 MB/s | 109 % | ahead |  |
| 13 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,711/s | 5,068/s | 113 % | ahead | server CPU/handshake 175 vs 197 µs |
| 14 | record layer | Keep-alive 1 KB over TLS — req/s | 61,732/s | 50,484/s | 122 % | ahead | TLS adds 1.63 µs CPU per request on NURL, 4.58 µs on Rust (TLS minus plaintext) |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,586/s | 1,291/s | 123 % | ahead | p50 632 vs 770 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,550/s | 1,188/s | 130 % | ahead | p50 646 vs 834 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 15,749/s | 11,412/s | 138 % | ahead |  |
| 18 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,713 MB/s | 1,016 MB/s | 169 % | ahead | server CPU 528 vs 963 ns/KB; the AEAD alone is 137 vs 246 ns/KB |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,671 | 100 % | 214 | 64.0 | 149 | 7,269 / 8,988 | 377 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,613 | 100 % | 216 | 59.1 | 157 | 6,930 / 8,725 | 369 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,711 | 100 % | 175 | 43.8 | 131 | 5,844 / 6,931 | 284 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 5,068 | 100 % | 197 | 41.3 | 156 | 7,508 / 10,388 | 264 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,787 | 100 % | 264 | 108 | 155 | 8,994 / 11,339 | 454 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,923 | 100 % | 254 | 84.2 | 170 | 8,253 / 10,354 | 443 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 4,017 | 100 % | 248 | 82.4 | 166 | 8,509 / 10,151 | 442 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,019 | 100 % | 248 | 71.8 | 176 | 9,327 / 11,896 | 429 | — |
| Full · RSA-2048 · X25519 | NURL | 1,018 | 100 % | 980 | 812 | 168 | 32,529 / 46,094 | 1,103 | — |
| Full · RSA-2048 · X25519 | RUST | 1,154 | 100 % | 864 | 700 | 164 | 27,594 / 41,479 | 958 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 61,732 | 100 % | 16.1 | 1,030 / 1,178 | 1.63 |
| NURL | plaintext | 68,932 | 100 % | 14.5 | 927 / 990 |  |
| RUST | TLS | 50,484 | 100 % | 19.7 | 1,278 / 1,383 | 4.58 |
| RUST | plaintext | 66,014 | 100 % | 15.1 | 986 / 1,040 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,713 | 88 % | 528 | 137 | — |
| NURL | chacha | 961 | 95 % | 1,012 | 500 | — |
| NURL | plain | 4,736 | 92 % | 198 | n/a | — |
| NURL | aes128+ktls | 858 | 69 % | 821 | 137 | yes |
| RUST | aes128 | 1,016 | 96 % | 963 | 246 | — |
| RUST | chacha | 914 | 94 % | 1,055 | 434 | — |
| RUST | plain | 3,292 | 94 % | 291 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,550 | 0.02 | 646 / 690 | 0 |
| full:/ | reqwest | 1,188 | 0.02 | 834 / 875 | 0 |
| resume:/ | http-client | 1,586 | 0.02 | 632 / 677 | 0 |
| resume:/ | reqwest | 1,291 | 0.02 | 770 / 821 | 0 |
| ka:/1k | http-client | 15,749 | 16.1 | 61.0 / 94.0 | 0 |
| ka:/1k | reqwest | 11,412 | 11.7 | 83.0 / 119 | 0 |
| ka:/1m | http-client | 902 | 946 | 1,106 / 1,158 | 0 |
| ka:/1m | reqwest | 827 | 867 | 1,197 / 1,315 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 10.7 | 8.69 | 81 % |
| X25519 shared | `adx` | 30.9 | 27.9 | 90 % |
| P-256 ECDH keygen | `adx` | 15.6 | 10.2 | 66 % |
| P-256 ECDH shared | `adx` | 70.2 | 51.5 | 73 % |
| ML-KEM-768 encaps | `avx2` | 18.3 | 12.8 | 70 % |
| ECDSA P-256 sign | `adx` | 20.3 | 17.8 | 88 % |
| ECDSA P-256 verify | `adx` | 71.6 | 57.8 | 81 % |
| RSA-2048 PSS sign | `adx` | 768 | 659 | 86 % |
| HKDF-Expand-Label | `sha-ni` | 0.14 | 0.29 | 213 % |
| SHA-256 16 KB | `sha-ni` | 10.4 | 10.4 | 100 % |
| AES-128-GCM seal 16 KB | `vaes` | 2.19 | 3.94 | 180 % |
| ChaCha20-Poly1305 seal 16 KB | `avx2` | 7.99 | 6.94 | 87 % |

## Environment

| Item | Value |
|---|---|
| CPU family | `amd-avx2-vaes-sha-adx` (vendor and flags; see bench/tls_bench/README.md) |
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| CPU vendor | `AuthenticAMD` |
| CPU flags (the crypto-relevant ones present) | `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `1b258243b084b165bdaec3f8fade4290d92de44a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41185082810 |
| NURL | `v0.82.0-8-g1b258243` |
| NURL_CPU_* masking | `none` |
| OPENSSL_ia32cap (aws-lc's CPUID mask) | `unset` |
| Rust | `rustc 1.99.1 (58cf8f9c3 2026-10-13)` |
| Cell durations (s) | `hs=15 lat=5 ka=10 client=6 prim_runs=3` |
| rustls | `0.23.46` |
| aws-lc-rs | `1.18.2` |
| hyper | `1.12.0` |
| tokio | `1.54.1` |
| reqwest | `0.12.28` |
| NURL CPU probes | `v3=1 aes=1 vaes=1 vaes512=0 sha=1 adx=1 ifma=0` |

### Reading these numbers

- **Read pairs, not cells.** Both servers ran on the same cores in the same run; a shared CI VM moves absolute numbers between runs by more than it moves the ratio.
- **A ratio belongs to its CPU family.** aws-lc and NURL each pick kernels by CPUID, so the same code can lead on one family and trail on another. Compare this report only with an earlier one of the same family; the index sets the families side by side.
- **CPU per operation is the absolute number.** Rates depend on how many cores the server had; server CPU per handshake / per request / per KB does not, and it is what the crypto budget is subtracted from.
- **The crypto budget is a floor, not a model.** It counts each primitive once at its single-core, warm-cache cost. *Rest* therefore also holds cache misses the microbenchmark does not see — a large *rest* with a small primitive gap points at the protocol code, the allocator or the I/O path.
- **The client rows include the library.** http-client and reqwest are measured as an application calls them (pooling, header handling, response assembly), not as bare TLS.
