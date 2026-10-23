# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-23T19:52:25Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 650/s | 2,563/s | 25 % | **major gap** | server CPU 1,538 vs 390 µs/handshake: of the 1,148 µs gap, 1,110 µs is primitive crypto (largest: RSA-2048 PSS sign, +1,082 µs), 38.2 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,588 µs | 496 µs | 31 % | **major gap** |  |
| 3 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 2,548/s | 5,230/s | 49 % | **gap** | server CPU 392 vs 191 µs/handshake: of the 201 µs gap, 184 µs is primitive crypto (largest: P-256 ECDH shared, +125 µs), 17.1 µs is protocol / runtime / I/O |
| 4 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 3,469/s | 5,416/s | 64 % | **gap** | server CPU 288 vs 184 µs/handshake: of the 104 µs gap, 68.2 µs is primitive crypto (largest: ECDSA P-256 sign, +31.1 µs), 35.3 µs is protocol / runtime / I/O |
| 5 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,201/s | 6,291/s | 67 % | **gap** | server CPU 238 vs 159 µs/handshake: of the 79.0 µs gap, 58.6 µs is primitive crypto (largest: ECDSA P-256 sign, +31.1 µs), 20.4 µs is protocol / runtime / I/O |
| 6 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 528 µs | 357 µs | 68 % | **gap** |  |
| 7 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 838 MB/s | 1,160 MB/s | 72 % | **gap** | server CPU 1,174 vs 833 ns/KB; the AEAD alone is 620 vs 387 ns/KB |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 439 µs | 342 µs | 78 % | behind |  |
| 9 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,578/s | 7,022/s | 79 % | behind | server CPU 179 vs 142 µs/handshake: of the 36.9 µs gap, 27.5 µs is primitive crypto (largest: X25519 shared, +12.5 µs), 9.38 µs is protocol / runtime / I/O |
| 10 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 334 µs | 299 µs | 90 % | behind |  |
| 11 | record layer | Keep-alive 1 KB over TLS — req/s | 87,625/s | 90,221/s | 97 % | parity | TLS adds 1.20 µs CPU per request on NURL, 1.10 µs on Rust (TLS minus plaintext) |
| 12 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 98,296/s | 100,350/s | 98 % | parity | not TLS: the HTTP/1.1 server itself |
| 13 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,963 MB/s | 1,921 MB/s | 102 % | parity | server CPU 487 vs 366 ns/KB; the AEAD alone is 119 vs 89.4 ns/KB |
| 14 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 228 µs | 233 µs | 102 % | parity |  |
| 15 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,721/s | 1,610/s | 107 % | ahead | p50 579 vs 614 µs per request |
| 16 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,698/s | 1,463/s | 116 % | ahead | p50 587 vs 678 µs per request |
| 17 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 24,905/s | 18,571/s | 134 % | ahead |  |
| 18 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 1,911 MB/s | 1,400 MB/s | 136 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,201 | 100 % | 238 | 110 | 128 | 2,975 / 12,955 | 334 | — |
| Full · ECDSA P-256 · X25519 | RUST | 6,291 | 100 % | 159 | 51.4 | 107 | 6,209 / 8,171 | 299 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,578 | 100 % | 179 | 63.6 | 115 | 5,270 / 9,158 | 228 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 7,022 | 100 % | 142 | 36.1 | 106 | 5,488 / 7,415 | 233 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 2,548 | 100 % | 392 | 256 | 135 | 9,765 / 23,911 | 528 | — |
| Full · ECDSA P-256 · P-256 | RUST | 5,230 | 100 % | 191 | 72.5 | 118 | 7,103 / 9,204 | 357 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 3,469 | 100 % | 288 | 133 | 155 | 3,803 / 16,470 | 439 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 5,416 | 100 % | 184 | 64.5 | 120 | 6,959 / 9,703 | 342 | — |
| Full · RSA-2048 · X25519 | NURL | 650 | 100 % | 1,538 | 1,388 | 150 | 46,968 / 92,668 | 1,588 | — |
| Full · RSA-2048 · X25519 | RUST | 2,563 | 100 % | 390 | 278 | 111 | 12,090 / 20,164 | 496 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 87,625 | 100 % | 11.4 | 754 / 841 | 1.20 |
| NURL | plaintext | 98,296 | 100 % | 10.2 | 675 / 769 |  |
| RUST | TLS | 90,221 | 100 % | 11.1 | 716 / 794 | 1.10 |
| RUST | plaintext | 100,350 | 100 % | 9.96 | 647 / 703 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,963 | 93 % | 487 | 119 | — |
| NURL | chacha | 838 | 96 % | 1,174 | 620 | — |
| NURL | plain | 4,835 | 91 % | 193 | n/a | — |
| NURL | aes128+ktls | 1,358 | 62 % | 466 | 119 | yes |
| RUST | aes128 | 1,921 | 69 % | 366 | 89.4 | — |
| RUST | chacha | 1,160 | 94 % | 833 | 387 | — |
| RUST | plain | 4,844 | 90 % | 191 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,698 | 0.02 | 587 / 646 | 0 |
| full:/ | reqwest | 1,463 | 0.02 | 678 / 731 | 0 |
| resume:/ | http-client | 1,721 | 0.02 | 579 / 639 | 0 |
| resume:/ | reqwest | 1,610 | 0.02 | 614 / 684 | 0 |
| ka:/1k | http-client | 24,905 | 25.5 | 39.0 / 52.0 | 0 |
| ka:/1k | reqwest | 18,571 | 19.0 | 52.0 / 67.0 | 0 |
| ka:/1m | http-client | 1,823 | 1,911 | 546 / 580 | 0 |
| ka:/1m | reqwest | 1,336 | 1,400 | 647 / 968 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 19.6 | 7.67 | 39 % |
| X25519 shared | 36.7 | 24.3 | 66 % |
| P-256 ECDH keygen | 33.3 | 8.89 | 27 % |
| P-256 ECDH shared | 169 | 44.2 | 26 % |
| ML-KEM-768 encaps | 22.7 | 13.1 | 58 % |
| ECDSA P-256 sign | 46.4 | 15.2 | 33 % |
| ECDSA P-256 verify | 218 | 49.9 | 23 % |
| RSA-2048 PSS sign | 1,324 | 242 | 18 % |
| HKDF-Expand-Label | 0.46 | 0.26 | 57 % |
| SHA-256 16 KB | 54.5 | 9.05 | 17 % |
| AES-128-GCM seal 16 KB | 1.90 | 1.43 | 75 % |
| ChaCha20-Poly1305 seal 16 KB | 9.91 | 6.19 | 62 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 9V74 80-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `89b5358941345b12ce864294869a151ed638095f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40013542364 |
| NURL | `v0.77.2-14-g89b53589` |
| Rust | `rustc 1.99.1 (58cf8f9c3 2026-10-13)` |
| Cell durations (s) | `hs=15 lat=5 ka=10 client=6 prim_runs=3` |
| rustls | `0.23.46` |
| aws-lc-rs | `1.18.2` |
| hyper | `1.12.0` |
| tokio | `1.54.1` |
| reqwest | `0.12.28` |

### Reading these numbers

- **Read pairs, not cells.** Both servers ran on the same cores in the same run; a shared CI VM moves absolute numbers between runs by more than it moves the ratio.
- **CPU per operation is the absolute number.** Rates depend on how many cores the server had; server CPU per handshake / per request / per KB does not, and it is what the crypto budget is subtracted from.
- **The crypto budget is a floor, not a model.** It counts each primitive once at its single-core, warm-cache cost. *Rest* therefore also holds cache misses the microbenchmark does not see — a large *rest* with a small primitive gap points at the protocol code, the allocator or the I/O path.
- **The client rows include the library.** http-client and reqwest are measured as an application calls them (pooling, header handling, response assembly), not as bare TLS.
