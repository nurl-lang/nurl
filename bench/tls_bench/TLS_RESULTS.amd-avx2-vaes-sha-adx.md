# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `amd-avx2-vaes-sha-adx`

Generated `2026-11-13T20:30:07Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `AMD EPYC 7763 64-Core Processor`, commit `ab45d9db114a`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/43501277406). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `amd-avx2-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 850 MB/s | 1,042 MB/s | 82 % | behind | server CPU 1,145 vs 927 ns/KB; the AEAD alone is 524 vs 433 ns/KB |
| 2 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 1,030/s | 1,158/s | 89 % | behind | server CPU 969 vs 863 µs/handshake: of the 106 µs gap, 107 µs is primitive crypto (largest: RSA-2048 PSS sign, +105 µs), NURL's protocol / runtime / I/O is 1.00 µs CHEAPER than Rust's |
| 3 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 281 µs | 258 µs | 92 % | behind |  |
| 4 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 456 µs | 421 µs | 92 % | behind |  |
| 5 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,053 µs | 990 µs | 94 % | behind |  |
| 6 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 417 µs | 404 µs | 97 % | parity |  |
| 7 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 4,059/s | 4,114/s | 99 % | parity | server CPU 246 vs 243 µs/handshake: of the 2.96 µs gap, 8.94 µs is primitive crypto (largest: ML-KEM-768 encaps, +5.08 µs), NURL's protocol / runtime / I/O is 5.98 µs CHEAPER than Rust's |
| 8 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,899/s | 3,929/s | 99 % | parity | server CPU 256 vs 254 µs/handshake: of the 2.12 µs gap, 15.5 µs is primitive crypto (largest: P-256 ECDH shared, +10.9 µs), NURL's protocol / runtime / I/O is 13.4 µs CHEAPER than Rust's |
| 9 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 376 µs | 379 µs | 101 % | parity |  |
| 10 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,763/s | 4,662/s | 102 % | parity | server CPU/handshake 209 vs 214 µs |
| 11 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 69,946/s | 67,249/s | 104 % | parity | not TLS: the HTTP/1.1 server itself |
| 12 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,764/s | 5,081/s | 113 % | ahead | server CPU/handshake 173 vs 196 µs |
| 13 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 947 MB/s | 813 MB/s | 116 % | ahead |  |
| 14 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,254 MB/s | 1,071 MB/s | 117 % | ahead | server CPU 683 vs 909 ns/KB; the AEAD alone is 135 vs 245 ns/KB |
| 15 | record layer | Keep-alive 1 KB over TLS — req/s | 62,599/s | 52,699/s | 119 % | ahead | TLS adds 1.63 µs CPU per request on NURL, 4.04 µs on Rust (TLS minus plaintext) |
| 16 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,595/s | 1,289/s | 124 % | ahead | p50 626 vs 770 µs per request |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,564/s | 1,193/s | 131 % | ahead | p50 639 vs 832 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 15,728/s | 11,547/s | 136 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,763 | 100 % | 209 | 62.9 | 146 | 7,131 / 8,595 | 376 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,662 | 100 % | 214 | 59.1 | 155 | 6,875 / 8,834 | 379 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,764 | 100 % | 173 | 43.1 | 130 | 5,793 / 7,011 | 281 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 5,081 | 100 % | 196 | 41.5 | 155 | 6,285 / 7,572 | 258 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,899 | 100 % | 256 | 99.4 | 157 | 8,762 / 10,857 | 417 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,929 | 100 % | 254 | 83.9 | 170 | 8,235 / 10,387 | 404 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 4,059 | 100 % | 246 | 80.7 | 165 | 8,384 / 10,347 | 456 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,114 | 100 % | 243 | 71.8 | 171 | 7,844 / 9,875 | 421 | — |
| Full · RSA-2048 · X25519 | NURL | 1,030 | 100 % | 969 | 807 | 161 | 32,173 / 45,301 | 1,053 | — |
| Full · RSA-2048 · X25519 | RUST | 1,158 | 100 % | 863 | 701 | 162 | 27,377 / 38,865 | 990 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 62,599 | 100 % | 15.9 | 1,020 / 1,127 | 1.63 |
| NURL | plaintext | 69,946 | 100 % | 14.3 | 912 / 986 |  |
| RUST | TLS | 52,699 | 100 % | 18.9 | 1,238 / 1,304 | 4.04 |
| RUST | plaintext | 67,249 | 100 % | 14.9 | 969 / 1,019 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,254 | 84 % | 683 | 135 | — |
| NURL | chacha | 850 | 95 % | 1,145 | 524 | — |
| NURL | plain | 4,253 | 93 % | 223 | n/a | — |
| NURL | aes128+ktls | 906 | 72 % | 819 | 135 | yes |
| RUST | aes128 | 1,071 | 95 % | 909 | 245 | — |
| RUST | chacha | 1,042 | 94 % | 927 | 433 | — |
| RUST | plain | 4,662 | 92 % | 201 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,564 | 0.02 | 639 / 680 | 0 |
| full:/ | reqwest | 1,193 | 0.02 | 832 / 863 | 0 |
| resume:/ | http-client | 1,595 | 0.02 | 626 / 667 | 0 |
| resume:/ | reqwest | 1,289 | 0.02 | 770 / 806 | 0 |
| ka:/1k | http-client | 15,728 | 16.1 | 61.0 / 87.0 | 0 |
| ka:/1k | reqwest | 11,547 | 11.8 | 83.0 / 110 | 0 |
| ka:/1m | http-client | 903 | 947 | 1,105 / 1,146 | 0 |
| ka:/1m | reqwest | 775 | 813 | 1,213 / 1,695 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 9.59 | 8.71 | 91 % |
| X25519 shared | `adx` | 31.3 | 28.1 | 90 % |
| P-256 ECDH keygen | `adx` | 15.1 | 10.3 | 68 % |
| P-256 ECDH shared | `adx` | 62.3 | 51.4 | 82 % |
| ML-KEM-768 encaps | `avx2` | 17.8 | 12.7 | 71 % |
| ECDSA P-256 sign | `adx` | 19.9 | 17.6 | 89 % |
| ECDSA P-256 verify | `adx` | 66.4 | 57.7 | 87 % |
| RSA-2048 PSS sign | `adx` | 764 | 659 | 86 % |
| HKDF-Expand-Label | `sha-ni` | 0.14 | 0.29 | 215 % |
| SHA-256 16 KB | `sha-ni` | 10.4 | 10.3 | 99 % |
| AES-128-GCM seal 16 KB | `vaes` | 2.15 | 3.92 | 182 % |
| ChaCha20-Poly1305 seal 16 KB | `avx2` | 8.39 | 6.93 | 83 % |

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
| Commit | `ab45d9db114a58fdab60f618c679e8af95643b5d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43501277406 |
| NURL | `v0.91.1-112-gab45d9db` |
| NURL_CPU_* masking | `none` |
| OPENSSL_ia32cap (aws-lc's CPUID mask) | `unset` |
| Rust | `rustc 1.100.0 (0ef1bc386 2026-11-09)` |
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
