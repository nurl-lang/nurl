# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `intel-avx512ifma-vaes-sha-adx`

Generated `2026-11-10T20:43:43Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `Intel(R) Xeon(R) 6973P-C`, commit `94ee1161a2fc`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/42897413140). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `intel-avx512ifma-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 1,323 MB/s | 1,533 MB/s | 86 % | behind | server CPU 589 vs 621 ns/KB; the AEAD alone is 272 vs 389 ns/KB |
| 2 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 310 µs | 287 µs | 93 % | behind |  |
| 3 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 7,164/s | 7,407/s | 97 % | parity | server CPU 139 vs 135 µs/handshake: of the 4.66 µs gap, 3.32 µs is primitive crypto (largest: ML-KEM-768 encaps, +2.16 µs), 1.34 µs is protocol / runtime / I/O |
| 4 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 460 µs | 447 µs | 97 % | parity |  |
| 5 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 151,351/s | 154,857/s | 98 % | parity | not TLS: the HTTP/1.1 server itself |
| 6 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 6,935/s | 7,092/s | 98 % | parity | server CPU 144 vs 141 µs/handshake: of the 3.20 µs gap, 9.03 µs is primitive crypto (largest: P-256 ECDH shared, +6.93 µs), NURL's protocol / runtime / I/O is 5.84 µs CHEAPER than Rust's |
| 7 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 2,633/s | 2,637/s | 100 % | parity | server CPU 379 vs 379 µs/handshake: of the 0.27 µs gap, 23.9 µs is primitive crypto (largest: RSA-2048 PSS sign, +23.8 µs), NURL's protocol / runtime / I/O is 23.7 µs CHEAPER than Rust's |
| 8 | record layer | Keep-alive 1 KB over TLS — req/s | 132,924/s | 130,849/s | 102 % | parity | TLS adds 0.89 µs CPU per request on NURL, 1.17 µs on Rust (TLS minus plaintext) |
| 9 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 8,765/s | 8,627/s | 102 % | parity | server CPU/handshake 114 vs 115 µs |
| 10 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 10,900/s | 10,715/s | 102 % | parity | server CPU/handshake 91.6 vs 93.2 µs |
| 11 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 150 µs | 157 µs | 105 % | parity |  |
| 12 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 265 µs | 280 µs | 106 % | ahead |  |
| 13 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 221 µs | 234 µs | 106 % | ahead |  |
| 14 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 3,520 MB/s | 3,086 MB/s | 114 % | ahead | server CPU 265 vs 312 ns/KB; the AEAD alone is 53.8 vs 55.5 ns/KB |
| 15 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 2,548 MB/s | 2,209 MB/s | 115 % | ahead |  |
| 16 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 39,603/s | 32,679/s | 121 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 2,899/s | 2,129/s | 136 % | ahead | p50 340 vs 459 µs per request |
| 18 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 2,636/s | 1,850/s | 143 % | ahead | p50 371 vs 530 µs per request |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 8,765 | 100 % | 114 | 43.2 | 70.7 | 3,877 / 5,187 | 221 | — |
| Full · ECDSA P-256 · X25519 | RUST | 8,627 | 99 % | 115 | 42.0 | 72.9 | 3,822 / 6,557 | 234 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 10,900 | 100 % | 91.6 | 28.3 | 63.4 | 3,035 / 4,018 | 150 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 10,715 | 100 % | 93.2 | 28.1 | 65.1 | 3,539 / 5,253 | 157 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 6,935 | 100 % | 144 | 69.7 | 74.3 | 4,946 / 6,451 | 265 | — |
| Full · ECDSA P-256 · P-256 | RUST | 7,092 | 100 % | 141 | 60.6 | 80.2 | 4,686 / 6,872 | 280 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 7,164 | 100 % | 139 | 55.1 | 84.2 | 4,736 / 6,339 | 310 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 7,407 | 100 % | 135 | 51.8 | 82.8 | 4,573 / 7,114 | 287 | — |
| Full · RSA-2048 · X25519 | NURL | 2,633 | 100 % | 379 | 306 | 72.9 | 12,641 / 17,655 | 460 | — |
| Full · RSA-2048 · X25519 | RUST | 2,637 | 100 % | 379 | 282 | 96.6 | 12,096 / 20,392 | 447 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 132,924 | 100 % | 7.49 | 478 / 571 | 0.89 |
| NURL | plaintext | 151,351 | 100 % | 6.60 | 420 / 499 |  |
| RUST | TLS | 130,849 | 100 % | 7.62 | 489 / 596 | 1.17 |
| RUST | plaintext | 154,857 | 100 % | 6.45 | 414 / 513 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 3,520 | 91 % | 265 | 53.8 | — |
| NURL | chacha | 1,323 | 76 % | 589 | 272 | — |
| NURL | plain | 5,923 | 88 % | 152 | n/a | — |
| NURL | aes128+ktls | 2,201 | 87 % | 403 | 53.8 | yes |
| RUST | aes128 | 3,086 | 94 % | 312 | 55.5 | — |
| RUST | chacha | 1,533 | 93 % | 621 | 389 | — |
| RUST | plain | 6,236 | 91 % | 149 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 2,636 | 0.04 | 371 / 447 | 0 |
| full:/ | reqwest | 1,850 | 0.03 | 530 / 605 | 0 |
| resume:/ | http-client | 2,899 | 0.04 | 340 / 391 | 0 |
| resume:/ | reqwest | 2,129 | 0.03 | 459 / 551 | 0 |
| ka:/1k | http-client | 39,603 | 40.6 | 24.0 / 35.0 | 0 |
| ka:/1k | reqwest | 32,679 | 33.5 | 29.0 / 42.0 | 0 |
| ka:/1m | http-client | 2,430 | 2,548 | 416 / 483 | 0 |
| ka:/1m | reqwest | 2,106 | 2,209 | 469 / 578 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 6.64 | 6.41 | 97 % |
| X25519 shared | `adx` | 19.9 | 18.5 | 93 % |
| P-256 ECDH keygen | `adx` | 11.0 | 8.38 | 76 % |
| P-256 ECDH shared | `adx` | 42.1 | 35.1 | 84 % |
| ML-KEM-768 encaps | `avx2` | 12.0 | 9.81 | 82 % |
| ECDSA P-256 sign | `adx` | 14.9 | 13.9 | 93 % |
| ECDSA P-256 verify | `adx` | 45.1 | 46.5 | 103 % |
| RSA-2048 PSS sign | `ifma` | 278 | 254 | 91 % |
| HKDF-Expand-Label | `sha-ni` | 0.11 | 0.20 | 192 % |
| SHA-256 16 KB | `sha-ni` | 8.18 | 8.15 | 100 % |
| AES-128-GCM seal 16 KB | `vaes512` | 0.86 | 0.89 | 103 % |
| ChaCha20-Poly1305 seal 16 KB | `avx512` | 4.34 | 6.23 | 143 % |

## Environment

| Item | Value |
|---|---|
| CPU family | `intel-avx512ifma-vaes-sha-adx` (vendor and flags; see bench/tls_bench/README.md) |
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | `Intel(R) Xeon(R) 6973P-C` |
| CPU vendor | `GenuineIntel` |
| CPU flags (the crypto-relevant ones present) | `aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq gfni avx512f avx512vl avx512bw avx512ifma avx512vbmi` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `94ee1161a2fc3b21ae5baf8094bbbbbfce6c9535` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42897413140 |
| NURL | `v0.90.0-107-g94ee1161` |
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
