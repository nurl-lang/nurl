# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `amd-avx2-vaes-sha-adx`

Generated `2026-11-11T18:11:10Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `AMD EPYC 7763 64-Core Processor`, commit `a013bfae93c3`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/43074559209). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `amd-avx2-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 1,022/s | 1,160/s | 88 % | behind | server CPU 977 vs 859 µs/handshake: of the 118 µs gap, 105 µs is primitive crypto (largest: RSA-2048 PSS sign, +105 µs), 12.2 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,059 µs | 954 µs | 90 % | behind |  |
| 3 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 355 µs | 336 µs | 95 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 4,030/s | 4,094/s | 98 % | parity | server CPU 247 vs 244 µs/handshake: of the 3.72 µs gap, 7.53 µs is primitive crypto (largest: ML-KEM-768 encaps, +5.05 µs), NURL's protocol / runtime / I/O is 3.81 µs CHEAPER than Rust's |
| 5 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 408 µs | 402 µs | 99 % | parity |  |
| 6 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,889/s | 3,884/s | 100 % | parity | server CPU 257 vs 256 µs/handshake: of the 0.18 µs gap, 15.9 µs is primitive crypto (largest: P-256 ECDH shared, +11.1 µs), NURL's protocol / runtime / I/O is 15.7 µs CHEAPER than Rust's |
| 7 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 413 µs | 420 µs | 102 % | parity |  |
| 8 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,674/s | 4,566/s | 102 % | parity | server CPU/handshake 213 vs 218 µs |
| 9 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 70,300/s | 67,974/s | 103 % | parity | not TLS: the HTTP/1.1 server itself |
| 10 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 284 µs | 304 µs | 107 % | ahead |  |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,720/s | 5,084/s | 112 % | ahead | server CPU/handshake 174 vs 196 µs |
| 12 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 928 MB/s | 815 MB/s | 114 % | ahead |  |
| 13 | record layer | Keep-alive 1 KB over TLS — req/s | 61,326/s | 51,633/s | 119 % | ahead | TLS adds 2.02 µs CPU per request on NURL, 4.58 µs on Rust (TLS minus plaintext) |
| 14 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 957 MB/s | 803 MB/s | 119 % | ahead | server CPU 1,015 vs 1,220 ns/KB; the AEAD alone is 521 vs 437 ns/KB |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,567/s | 1,277/s | 123 % | ahead | p50 637 vs 776 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,531/s | 1,167/s | 131 % | ahead | p50 651 vs 848 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 15,348/s | 11,347/s | 135 % | ahead |  |
| 18 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,819 MB/s | 1,244 MB/s | 146 % | ahead | server CPU 457 vs 780 ns/KB; the AEAD alone is 134 vs 245 ns/KB |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,674 | 100 % | 213 | 61.3 | 152 | 7,263 / 8,748 | 355 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,566 | 100 % | 218 | 58.9 | 160 | 8,101 / 10,564 | 336 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,720 | 100 % | 174 | 41.3 | 133 | 5,844 / 6,932 | 284 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 5,084 | 100 % | 196 | 41.3 | 155 | 6,279 / 7,617 | 304 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,889 | 100 % | 257 | 99.4 | 157 | 8,786 / 10,860 | 408 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,884 | 100 % | 256 | 83.5 | 173 | 9,647 / 12,558 | 402 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 4,030 | 100 % | 247 | 79.1 | 168 | 8,443 / 10,229 | 413 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,094 | 100 % | 244 | 71.6 | 172 | 7,865 / 9,882 | 420 | — |
| Full · RSA-2048 · X25519 | NURL | 1,022 | 100 % | 977 | 806 | 170 | 32,754 / 45,512 | 1,059 | — |
| Full · RSA-2048 · X25519 | RUST | 1,160 | 100 % | 859 | 701 | 158 | 27,369 / 39,691 | 954 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 61,326 | 100 % | 16.2 | 1,043 / 1,146 | 2.02 |
| NURL | plaintext | 70,300 | 100 % | 14.2 | 910 / 974 |  |
| RUST | TLS | 51,633 | 100 % | 19.3 | 1,257 / 1,338 | 4.58 |
| RUST | plaintext | 67,974 | 100 % | 14.7 | 963 / 1,021 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,819 | 81 % | 457 | 134 | — |
| NURL | chacha | 957 | 95 % | 1,015 | 521 | — |
| NURL | plain | 3,907 | 94 % | 246 | n/a | — |
| NURL | aes128+ktls | 926 | 76 % | 839 | 134 | yes |
| RUST | aes128 | 1,244 | 95 % | 780 | 245 | — |
| RUST | chacha | 803 | 96 % | 1,220 | 437 | — |
| RUST | plain | 3,719 | 93 % | 255 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,531 | 0.02 | 651 / 701 | 0 |
| full:/ | reqwest | 1,167 | 0.02 | 848 / 902 | 0 |
| resume:/ | http-client | 1,567 | 0.02 | 637 / 691 | 0 |
| resume:/ | reqwest | 1,277 | 0.02 | 776 / 829 | 0 |
| ka:/1k | http-client | 15,348 | 15.7 | 63.0 / 89.0 | 0 |
| ka:/1k | reqwest | 11,347 | 11.6 | 84.0 / 112 | 0 |
| ka:/1m | http-client | 885 | 928 | 1,128 / 1,172 | 0 |
| ka:/1m | reqwest | 778 | 815 | 1,215 / 1,750 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 9.27 | 8.68 | 94 % |
| X25519 shared | `adx` | 29.9 | 28.0 | 94 % |
| P-256 ECDH keygen | `adx` | 15.0 | 10.2 | 68 % |
| P-256 ECDH shared | `adx` | 62.3 | 51.2 | 82 % |
| ML-KEM-768 encaps | `avx2` | 17.8 | 12.7 | 72 % |
| ECDSA P-256 sign | `adx` | 20.0 | 17.5 | 88 % |
| ECDSA P-256 verify | `adx` | 66.8 | 57.7 | 86 % |
| RSA-2048 PSS sign | `adx` | 765 | 659 | 86 % |
| HKDF-Expand-Label | `sha-ni` | 0.14 | 0.29 | 215 % |
| SHA-256 16 KB | `sha-ni` | 10.4 | 10.3 | 100 % |
| AES-128-GCM seal 16 KB | `vaes` | 2.15 | 3.92 | 183 % |
| ChaCha20-Poly1305 seal 16 KB | `avx2` | 8.34 | 7.00 | 84 % |

## Environment

| Item | Value |
|---|---|
| CPU family | `amd-avx2-vaes-sha-adx` (vendor and flags; see bench/tls_bench/README.md) |
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | `AMD EPYC 7763 64-Core Processor` |
| CPU vendor | `AuthenticAMD` |
| CPU flags (the crypto-relevant ones present) | `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `a013bfae93c3f95925d589a5909e374b9705b502` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43074559209 |
| NURL | `v0.91.0-7-ga013bfae` |
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
