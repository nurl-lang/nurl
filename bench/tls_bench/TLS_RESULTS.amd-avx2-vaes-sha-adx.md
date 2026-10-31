# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `amd-avx2-vaes-sha-adx`

Generated `2026-10-31T08:07:27Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `AMD EPYC 7763 64-Core Processor`, commit `56573129a8a6`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/41182972443). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `amd-avx2-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 990/s | 1,146/s | 86 % | behind | server CPU 1,007 vs 871 µs/handshake: of the 137 µs gap, 110 µs is primitive crypto (largest: RSA-2048 PSS sign, +107 µs), 26.8 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,115 µs | 970 µs | 87 % | behind |  |
| 3 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 376 µs | 351 µs | 93 % | behind |  |
| 4 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,423 MB/s | 1,495 MB/s | 95 % | parity | server CPU 610 vs 643 ns/KB; the AEAD alone is 137 vs 247 ns/KB |
| 5 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,730/s | 3,877/s | 96 % | parity | server CPU 268 vs 257 µs/handshake: of the 10.3 µs gap, 24.9 µs is primitive crypto (largest: P-256 ECDH shared, +19.3 µs), NURL's protocol / runtime / I/O is 14.6 µs CHEAPER than Rust's |
| 6 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 283 µs | 276 µs | 98 % | parity |  |
| 7 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 69,046/s | 70,759/s | 98 % | parity | not TLS: the HTTP/1.1 server itself |
| 8 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 456 µs | 445 µs | 98 % | parity |  |
| 9 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,979/s | 4,031/s | 99 % | parity | server CPU 251 vs 247 µs/handshake: of the 3.23 µs gap, 10.7 µs is primitive crypto (largest: ML-KEM-768 encaps, +5.47 µs), NURL's protocol / runtime / I/O is 7.44 µs CHEAPER than Rust's |
| 10 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 421 µs | 421 µs | 100 % | parity |  |
| 11 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,626/s | 4,581/s | 101 % | parity | server CPU/handshake 216 vs 218 µs |
| 12 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 881 MB/s | 819 MB/s | 108 % | ahead | server CPU 981 vs 1,188 ns/KB; the AEAD alone is 499 vs 434 ns/KB |
| 13 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,674/s | 5,128/s | 111 % | ahead | server CPU/handshake 176 vs 194 µs |
| 14 | record layer | Keep-alive 1 KB over TLS — req/s | 59,828/s | 51,013/s | 117 % | ahead | TLS adds 2.18 µs CPU per request on NURL, 5.42 µs on Rust (TLS minus plaintext) |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,577/s | 1,296/s | 122 % | ahead | p50 633 vs 764 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,539/s | 1,176/s | 131 % | ahead | p50 648 vs 839 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 927 MB/s | 688 MB/s | 135 % | ahead |  |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 15,840/s | 11,477/s | 138 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,626 | 100 % | 216 | 64.1 | 152 | 7,323 / 8,970 | 376 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,581 | 100 % | 218 | 58.9 | 159 | 8,091 / 10,398 | 351 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,674 | 100 % | 176 | 43.8 | 132 | 5,892 / 7,128 | 283 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 5,128 | 100 % | 194 | 41.3 | 153 | 7,198 / 9,148 | 276 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,730 | 100 % | 268 | 109 | 159 | 9,160 / 11,352 | 456 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,877 | 100 % | 257 | 83.8 | 173 | 8,333 / 10,654 | 445 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,979 | 100 % | 251 | 82.3 | 168 | 8,554 / 10,424 | 421 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,031 | 100 % | 247 | 71.7 | 176 | 7,961 / 10,554 | 421 | — |
| Full · RSA-2048 · X25519 | NURL | 990 | 100 % | 1,007 | 813 | 194 | 33,443 / 47,095 | 1,115 | — |
| Full · RSA-2048 · X25519 | RUST | 1,146 | 100 % | 871 | 703 | 167 | 27,790 / 39,700 | 970 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 59,828 | 100 % | 16.7 | 1,065 / 1,195 | 2.18 |
| NURL | plaintext | 69,046 | 100 % | 14.5 | 924 / 999 |  |
| RUST | TLS | 51,013 | 100 % | 19.5 | 1,270 / 1,363 | 5.42 |
| RUST | plaintext | 70,759 | 100 % | 14.1 | 938 / 1,041 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,423 | 85 % | 610 | 137 | — |
| NURL | chacha | 881 | 84 % | 981 | 499 | — |
| NURL | plain | 4,033 | 93 % | 237 | n/a | — |
| NURL | aes128+ktls | 863 | 70 % | 827 | 137 | yes |
| RUST | aes128 | 1,495 | 94 % | 643 | 247 | — |
| RUST | chacha | 819 | 95 % | 1,188 | 434 | — |
| RUST | plain | 3,470 | 94 % | 276 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,539 | 0.02 | 648 / 718 | 0 |
| full:/ | reqwest | 1,176 | 0.02 | 839 / 923 | 0 |
| resume:/ | http-client | 1,577 | 0.02 | 633 / 704 | 0 |
| resume:/ | reqwest | 1,296 | 0.02 | 764 / 840 | 0 |
| ka:/1k | http-client | 15,840 | 16.2 | 60.0 / 94.0 | 0 |
| ka:/1k | reqwest | 11,477 | 11.8 | 83.0 / 120 | 0 |
| ka:/1m | http-client | 884 | 927 | 1,126 / 1,198 | 0 |
| ka:/1m | reqwest | 656 | 688 | 1,324 / 1,807 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 10.7 | 8.69 | 81 % |
| X25519 shared | `adx` | 30.9 | 28.0 | 90 % |
| P-256 ECDH keygen | `adx` | 15.6 | 10.3 | 66 % |
| P-256 ECDH shared | `adx` | 70.6 | 51.4 | 73 % |
| ML-KEM-768 encaps | `avx2` | 18.3 | 12.8 | 70 % |
| ECDSA P-256 sign | `adx` | 20.3 | 17.6 | 87 % |
| ECDSA P-256 verify | `adx` | 71.6 | 57.9 | 81 % |
| RSA-2048 PSS sign | `adx` | 769 | 662 | 86 % |
| HKDF-Expand-Label | `sha-ni` | 0.14 | 0.29 | 215 % |
| SHA-256 16 KB | `sha-ni` | 10.4 | 10.3 | 99 % |
| AES-128-GCM seal 16 KB | `vaes` | 2.19 | 3.95 | 180 % |
| ChaCha20-Poly1305 seal 16 KB | `avx2` | 7.99 | 6.95 | 87 % |

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
| Commit | `56573129a8a6a64db5aa57694dc5a78372a7e5e1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41182972443 |
| NURL | `v0.82.0-6-g56573129` |
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
