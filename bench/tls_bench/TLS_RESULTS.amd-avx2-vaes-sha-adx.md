# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs) — CPU family `amd-avx2-vaes-sha-adx`

Generated `2026-11-14T04:46:00Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**) on `AMD EPYC 7763 64-Core Processor`, commit `ede65cf52ce9`, [CI run](https://github.com/nurl-lang/nurl/actions/runs/43557846887). **Do not edit by hand** — the next run on this CPU family overwrites it; the index of every family is [`TLS_RESULTS.md`](TLS_RESULTS.md).

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first, on CPU family `amd-avx2-vaes-sha-adx`. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,089 µs | 951 µs | 87 % | behind |  |
| 2 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 1,030/s | 1,167/s | 88 % | behind | server CPU 968 vs 855 µs/handshake: of the 113 µs gap, 106 µs is primitive crypto (largest: RSA-2048 PSS sign, +104 µs), 7.55 µs is protocol / runtime / I/O |
| 3 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,256 MB/s | 1,418 MB/s | 89 % | behind | server CPU 681 vs 680 ns/KB; the AEAD alone is 135 vs 245 ns/KB |
| 4 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 448 µs | 411 µs | 92 % | behind |  |
| 5 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,915/s | 3,957/s | 99 % | parity | server CPU 255 vs 252 µs/handshake: of the 2.54 µs gap, 15.5 µs is primitive crypto (largest: P-256 ECDH shared, +11.0 µs), NURL's protocol / runtime / I/O is 13.0 µs CHEAPER than Rust's |
| 6 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 4,108/s | 4,131/s | 99 % | parity | server CPU 243 vs 241 µs/handshake: of the 1.46 µs gap, 8.96 µs is primitive crypto (largest: ML-KEM-768 encaps, +5.06 µs), NURL's protocol / runtime / I/O is 7.50 µs CHEAPER than Rust's |
| 7 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 845 MB/s | 848 MB/s | 100 % | parity | server CPU 949 vs 1,151 ns/KB; the AEAD alone is 520 vs 433 ns/KB |
| 8 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,772/s | 4,629/s | 103 % | parity | server CPU/handshake 209 vs 216 µs |
| 9 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 427 µs | 448 µs | 105 % | parity |  |
| 10 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 287 µs | 302 µs | 105 % | ahead |  |
| 11 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 71,546/s | 66,819/s | 107 % | ahead | not TLS: the HTTP/1.1 server itself |
| 12 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 345 µs | 375 µs | 109 % | ahead |  |
| 13 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,833/s | 5,211/s | 112 % | ahead | server CPU/handshake 171 vs 192 µs |
| 14 | record layer | Keep-alive 1 KB over TLS — req/s | 61,925/s | 51,726/s | 120 % | ahead | TLS adds 2.11 µs CPU per request on NURL, 4.32 µs on Rust (TLS minus plaintext) |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,595/s | 1,286/s | 124 % | ahead | p50 627 vs 771 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,558/s | 1,183/s | 132 % | ahead | p50 642 vs 839 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 932 MB/s | 697 MB/s | 134 % | ahead |  |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 15,036/s | 11,188/s | 134 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,772 | 100 % | 209 | 62.9 | 146 | 7,116 / 8,749 | 345 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,629 | 100 % | 216 | 59.0 | 157 | 8,042 / 10,150 | 375 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,833 | 100 % | 171 | 43.0 | 128 | 5,742 / 6,822 | 287 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 5,211 | 100 % | 192 | 41.2 | 150 | 7,117 / 8,898 | 302 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,915 | 100 % | 255 | 99.3 | 155 | 8,711 / 10,914 | 427 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,957 | 100 % | 252 | 83.8 | 168 | 9,513 / 11,842 | 448 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 4,108 | 100 % | 243 | 80.6 | 162 | 8,292 / 10,051 | 448 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,131 | 100 % | 241 | 71.7 | 170 | 7,790 / 10,072 | 411 | — |
| Full · RSA-2048 · X25519 | NURL | 1,030 | 100 % | 968 | 807 | 162 | 32,164 / 45,720 | 1,089 | — |
| Full · RSA-2048 · X25519 | RUST | 1,167 | 100 % | 855 | 701 | 154 | 27,313 / 40,219 | 951 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 61,925 | 100 % | 16.1 | 1,033 / 1,158 | 2.11 |
| NURL | plaintext | 71,546 | 100 % | 14.0 | 893 / 953 |  |
| RUST | TLS | 51,726 | 100 % | 19.3 | 1,249 / 1,314 | 4.32 |
| RUST | plaintext | 66,819 | 100 % | 14.9 | 973 / 1,036 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,256 | 84 % | 681 | 135 | — |
| NURL | chacha | 845 | 78 % | 949 | 520 | — |
| NURL | plain | 4,207 | 93 % | 226 | n/a | — |
| NURL | aes128+ktls | 783 | 91 % | 1,193 | 135 | yes |
| RUST | aes128 | 1,418 | 94 % | 680 | 245 | — |
| RUST | chacha | 848 | 95 % | 1,151 | 433 | — |
| RUST | plain | 3,528 | 93 % | 270 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,558 | 0.02 | 642 / 683 | 0 |
| full:/ | reqwest | 1,183 | 0.02 | 839 / 870 | 0 |
| resume:/ | http-client | 1,595 | 0.02 | 627 / 667 | 0 |
| resume:/ | reqwest | 1,286 | 0.02 | 771 / 804 | 0 |
| ka:/1k | http-client | 15,036 | 15.4 | 64.0 / 89.0 | 0 |
| ka:/1k | reqwest | 11,188 | 11.5 | 86.0 / 113 | 0 |
| ka:/1m | http-client | 888 | 932 | 1,121 / 1,167 | 0 |
| ka:/1m | reqwest | 664 | 697 | 1,300 / 1,740 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs. *NURL kernel* is the implementation the module says it engages on this CPU (`prims --tiers`: `aes_gcm_cpu_tier`, `rsa_cpu_tier`, …).

| Primitive | NURL kernel | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|---|--:|--:|--:|
| X25519 keygen | `adx` | 9.58 | 8.67 | 91 % |
| X25519 shared | `adx` | 31.3 | 27.9 | 89 % |
| P-256 ECDH keygen | `adx` | 15.1 | 10.2 | 68 % |
| P-256 ECDH shared | `adx` | 62.2 | 51.2 | 82 % |
| ML-KEM-768 encaps | `avx2` | 17.8 | 12.7 | 72 % |
| ECDSA P-256 sign | `adx` | 19.8 | 17.7 | 89 % |
| ECDSA P-256 verify | `adx` | 66.6 | 57.7 | 87 % |
| RSA-2048 PSS sign | `adx` | 764 | 660 | 86 % |
| HKDF-Expand-Label | `sha-ni` | 0.13 | 0.29 | 216 % |
| SHA-256 16 KB | `sha-ni` | 10.4 | 10.3 | 100 % |
| AES-128-GCM seal 16 KB | `vaes` | 2.16 | 3.92 | 182 % |
| ChaCha20-Poly1305 seal 16 KB | `avx2` | 8.32 | 6.93 | 83 % |

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
| Commit | `ede65cf52ce96593ff73d62343a11d24a1a5081d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43557846887 |
| NURL | `v0.91.1-118-gede65cf5` |
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
