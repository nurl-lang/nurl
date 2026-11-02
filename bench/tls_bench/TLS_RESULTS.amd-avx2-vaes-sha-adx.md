# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `amd-avx2-vaes-sha-adx`

Generated `2026-11-02T08:25:02Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `AMD EPYC 7763 64-Core Processor`, commit `38c8f6c8bc1c`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/41412304507). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `amd-avx2-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 989/s | 1,138/s | 87 % | behind | server CPU 1,009 vs 876 µs/handshake: of the 132 µs gap, 99.8 µs is primitive crypto (largest: RSA-2048 PSS sign, +99.5 µs), 32.7 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,101 µs | 972 µs | 88 % | behind |  |
| 3 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 454 µs | 420 µs | 93 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,614/s | 3,792/s | 95 % | parity | server CPU 276 vs 263 µs/handshake: of the 13.1 µs gap, 15.3 µs is primitive crypto (largest: P-256 ECDH shared, +11.0 µs), NURL's protocol / runtime / I/O is 2.13 µs CHEAPER than Rust's |
| 5 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 381 µs | 369 µs | 97 % | parity |  |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,740/s | 3,853/s | 97 % | parity | server CPU 267 vs 259 µs/handshake: of the 7.64 µs gap, 7.53 µs is primitive crypto (largest: ML-KEM-768 encaps, +5.12 µs), 0.11 µs is protocol / runtime / I/O |
| 7 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,485/s | 4,503/s | 100 % | parity | server CPU 222 vs 221 µs/handshake: of the 0.91 µs gap, 2.41 µs is primitive crypto (largest: ECDSA P-256 sign, +2.12 µs), NURL's protocol / runtime / I/O is 1.50 µs CHEAPER than Rust's |
| 8 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 69,719/s | 69,402/s | 100 % | parity | not TLS: the HTTP/1.1 server itself |
| 9 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 932 MB/s | 917 MB/s | 102 % | parity | server CPU 1,030 vs 1,059 ns/KB; the AEAD alone is 524 vs 434 ns/KB |
| 10 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 247 µs | 263 µs | 106 % | ahead |  |
| 11 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 409 µs | 437 µs | 107 % | ahead |  |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,410/s | 4,960/s | 109 % | ahead | server CPU/handshake 184 vs 201 µs |
| 13 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 918 MB/s | 838 MB/s | 110 % | ahead |  |
| 14 | record layer | Keep-alive 1 KB over TLS — req/s | 61,123/s | 51,706/s | 118 % | ahead | TLS adds 1.97 µs CPU per request on NURL, 4.87 µs on Rust (TLS minus plaintext) |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,576/s | 1,282/s | 123 % | ahead | p50 636 vs 774 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,538/s | 1,169/s | 132 % | ahead | p50 650 vs 846 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 15,289/s | 11,358/s | 135 % | ahead |  |
| 18 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,592 MB/s | 987 MB/s | 161 % | ahead | server CPU 535 vs 991 ns/KB; the AEAD alone is 138 vs 246 ns/KB |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,485 | 100 % | 222 | 61.3 | 161 | 7,538 / 9,295 | 381 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,503 | 100 % | 221 | 58.9 | 163 | 7,095 / 9,152 | 369 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,410 | 100 % | 184 | 41.7 | 143 | 6,146 / 7,330 | 247 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 4,960 | 100 % | 201 | 41.4 | 160 | 6,431 / 7,848 | 263 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,614 | 100 % | 276 | 99.0 | 177 | 9,430 / 11,595 | 409 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,792 | 100 % | 263 | 83.7 | 179 | 9,885 / 12,625 | 437 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,740 | 100 % | 267 | 79.2 | 187 | 9,065 / 10,991 | 454 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 3,853 | 100 % | 259 | 71.7 | 187 | 9,532 / 12,167 | 420 | — |
| Full · RSA-2048 · X25519 | NURL | 989 | 100 % | 1,009 | 802 | 207 | 33,583 / 46,500 | 1,101 | — |
| Full · RSA-2048 · X25519 | RUST | 1,138 | 100 % | 876 | 702 | 174 | 27,967 / 40,830 | 972 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 61,123 | 100 % | 16.3 | 1,042 / 1,166 | 1.97 |
| NURL | plaintext | 69,719 | 100 % | 14.3 | 919 / 999 |  |
| RUST | TLS | 51,706 | 100 % | 19.3 | 1,262 / 1,346 | 4.87 |
| RUST | plaintext | 69,402 | 100 % | 14.4 | 950 / 1,022 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,592 | 83 % | 535 | 138 | — |
| NURL | chacha | 932 | 94 % | 1,030 | 524 | — |
| NURL | plain | 3,957 | 93 % | 240 | n/a | — |
| NURL | aes128+ktls | 934 | 65 % | 714 | 138 | yes |
| RUST | aes128 | 987 | 96 % | 991 | 246 | — |
| RUST | chacha | 917 | 95 % | 1,059 | 434 | — |
| RUST | plain | 4,648 | 91 % | 201 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,538 | 0.02 | 650 / 702 | 0 |
| full:/ | reqwest | 1,169 | 0.02 | 846 / 902 | 0 |
| resume:/ | http-client | 1,576 | 0.02 | 636 / 686 | 0 |
| resume:/ | reqwest | 1,282 | 0.02 | 774 / 824 | 0 |
| ka:/1k | http-client | 15,289 | 15.7 | 63.0 / 97.0 | 0 |
| ka:/1k | reqwest | 11,358 | 11.6 | 84.0 / 119 | 0 |
| ka:/1m | http-client | 875 | 918 | 1,139 / 1,186 | 0 |
| ka:/1m | reqwest | 799 | 838 | 1,200 / 1,705 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 9.43 | 8.69 | 92 % |
| X25519 shared | `adx` | 30.1 | 28.0 | 93 % |
| P-256 ECDH keygen | `adx` | 14.9 | 10.2 | 69 % |
| P-256 ECDH shared | `adx` | 62.3 | 51.3 | 82 % |
| ML-KEM-768 encaps | `avx2` | 17.9 | 12.8 | 71 % |
| ECDSA P-256 sign | `adx` | 19.7 | 17.6 | 89 % |
| ECDSA P-256 verify | `adx` | 66.6 | 57.8 | 87 % |
| RSA-2048 PSS sign | `adx` | 760 | 660 | 87 % |
| HKDF-Expand-Label | `sha-ni` | 0.14 | 0.29 | 216 % |
| SHA-256 16 KB | `sha-ni` | 10.4 | 10.4 | 100 % |
| AES-128-GCM seal 16 KB | `vaes` | 2.20 | 3.93 | 179 % |
| ChaCha20-Poly1305 seal 16 KB | `avx2` | 8.38 | 6.94 | 83 % |

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
| Commit | `38c8f6c8bc1c1b9f9e9772bbaaa70b49f166774c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41412304507 |
| NURL | `v0.84.0-13-g38c8f6c8` |
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
