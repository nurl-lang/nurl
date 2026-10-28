# NURL TLS benchmark — NURL vs Rust (rustls / aws-lc-rs)

Generated `2026-10-28T09:37:05Z` by `bench/tls_bench/run_tls.sh` (MODE=**full**). **Do not edit by hand** — the next run overwrites it.

Every cost a TLS 1.3 HTTP stack pays — handshakes (full, resumed, per group and certificate), the record layer on small and large responses, and the client side — measured against the stack production Rust deploys: rustls on aws-lc-rs (assembly AES-GCM and X25519, the X25519MLKEM768 hybrid), hyper on tokio, reqwest. The NURL server is the `packages/http` HttpApp, the NURL client `packages/http-client`. Servers pinned to cores `0-0`, the load generator to `1-3`.

## Where to focus

NURL's result as a share of Rust's (100 % = parity; for latencies the inverse, so higher is always better), worst first. The last column is what the measurements below say the gap is made of.

| # | Area | Metric | NURL | Rust | NURL / Rust | Verdict | What the gap is |
|--:|---|---|--:|--:|--:|---|---|
| 1 | server handshake | Full · RSA-2048 · X25519 — handshakes/s | 815/s | 1,062/s | 77 % | behind | server CPU 1,224 vs 939 µs/handshake: of the 285 µs gap, 255 µs is primitive crypto (largest: RSA-2048 PSS sign, +252 µs), 30.6 µs is protocol / runtime / I/O |
| 2 | server handshake | Full · RSA-2048 · X25519 — unloaded latency p50 | 1,335 µs | 1,077 µs | 81 % | behind |  |
| 3 | server handshake | Resumed · X25519 (psk_dhe_ke) — unloaded latency p50 | 279 µs | 257 µs | 92 % | behind |  |
| 4 | record layer | Keep-alive 1 KB plaintext — req/s (baseline) | 77,193/s | 83,562/s | 92 % | behind | not TLS: the HTTP/1.1 server itself |
| 5 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — unloaded latency p50 | 467 µs | 433 µs | 93 % | behind |  |
| 6 | server handshake | Full · ECDSA P-256 · P-256 — handshakes/s | 3,729/s | 3,985/s | 94 % | behind | server CPU 268 vs 250 µs/handshake: of the 17.4 µs gap, 37.3 µs is primitive crypto (largest: P-256 ECDH shared, +30.5 µs), NURL's protocol / runtime / I/O is 19.9 µs CHEAPER than Rust's |
| 7 | bulk | 1 MB bodies, one connection, ChaCha20-Poly1305 — MB/s | 837 MB/s | 877 MB/s | 95 % | parity | server CPU 1,083 vs 1,100 ns/KB; the AEAD alone is 584 vs 499 ns/KB |
| 8 | server handshake | Full · ECDSA P-256 · X25519MLKEM768 — handshakes/s | 4,089/s | 4,212/s | 97 % | parity | server CPU 244 vs 237 µs/handshake: of the 7.32 µs gap, 10.4 µs is primitive crypto (largest: ML-KEM-768 encaps, +4.33 µs), NURL's protocol / runtime / I/O is 3.05 µs CHEAPER than Rust's |
| 9 | record layer | Keep-alive 1 KB over TLS — req/s | 67,744/s | 68,410/s | 99 % | parity | TLS adds 1.76 µs CPU per request on NURL, 2.59 µs on Rust (TLS minus plaintext) |
| 10 | server handshake | Full · ECDSA P-256 · X25519 — handshakes/s | 4,855/s | 4,843/s | 100 % | parity | server CPU/handshake 205 vs 206 µs |
| 11 | server handshake | Full · ECDSA P-256 · X25519 — unloaded latency p50 | 355 µs | 359 µs | 101 % | parity |  |
| 12 | server handshake | Full · ECDSA P-256 · P-256 — unloaded latency p50 | 449 µs | 455 µs | 101 % | parity |  |
| 13 | server handshake | Resumed · X25519 (psk_dhe_ke) — handshakes/s | 5,890/s | 5,482/s | 107 % | ahead | server CPU/handshake 169 vs 182 µs |
| 14 | client (http-client vs reqwest) | New connection per request, resumed — req/s | 1,566/s | 1,270/s | 123 % | ahead | p50 633 vs 779 µs per request |
| 15 | bulk | 1 MB bodies, one connection, AES-128-GCM — MB/s | 1,287 MB/s | 1,041 MB/s | 124 % | ahead | server CPU 478 vs 892 ns/KB; the AEAD alone is 146 vs 275 ns/KB |
| 16 | client (http-client vs reqwest) | Keep-alive 1 MB bodies — MB/s | 935 MB/s | 738 MB/s | 127 % | ahead |  |
| 17 | client (http-client vs reqwest) | New connection per request, full handshake — req/s | 1,521/s | 1,130/s | 135 % | ahead | p50 653 vs 867 µs per request |
| 18 | client (http-client vs reqwest) | Keep-alive 1 KB — req/s | 19,478/s | 14,433/s | 135 % | ahead |  |

## Server handshakes

Saturation: hs=15 lat=5 ka=10 client=6 prim_runs=3 — a fresh TCP + TLS connection per request (`Connection: close`, 14-byte body), closed loop, client pins one group and AES-128-GCM. *Server CPU / handshake* is the server process's utime + stime over the cell divided by the handshakes completed. *Crypto budget* is the sum of the server's primitives for that handshake from the primitive table (key share + shared secret [+ ML-KEM encaps] [+ signature] + 16× HKDF-Expand-Label); *rest* = CPU − budget: the protocol code, allocation, the runtime and the socket I/O. A server utilisation below 85 % means the generator, not the server, set the rate (†); ‡ marks a cell with fewer than 50 handshakes in the window, too few for a CPU-per-handshake figure.

| Handshake | Server | handshakes/s | server util | CPU / hs (µs) | crypto budget (µs) | rest (µs) | latency p50 / p99 under load (µs) | unloaded p50 (µs) | resumed |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| Full · ECDSA P-256 · X25519 | NURL | 4,855 | 100 % | 205 | 72.1 | 133 | 6,999 / 8,544 | 355 | — |
| Full · ECDSA P-256 · X25519 | RUST | 4,843 | 100 % | 206 | 66.1 | 140 | 7,635 / 9,857 | 359 | — |
| Resumed · X25519 (psk_dhe_ke) | NURL | 5,890 | 100 % | 169 | 49.4 | 120 | 5,668 / 6,694 | 279 | 100 % |
| Resumed · X25519 (psk_dhe_ke) | RUST | 5,482 | 100 % | 182 | 46.5 | 135 | 6,740 / 8,688 | 257 | 100 % |
| Full · ECDSA P-256 · P-256 | NURL | 3,729 | 100 % | 268 | 131 | 137 | 9,137 / 11,471 | 449 | — |
| Full · ECDSA P-256 · P-256 | RUST | 3,985 | 100 % | 250 | 93.3 | 157 | 8,136 / 10,900 | 455 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | NURL | 4,089 | 100 % | 244 | 92.4 | 152 | 8,301 / 10,296 | 467 | — |
| Full · ECDSA P-256 · X25519MLKEM768 | RUST | 4,212 | 100 % | 237 | 82.0 | 155 | 9,289 / 12,208 | 433 | — |
| Full · RSA-2048 · X25519 | NURL | 815 | 100 % | 1,224 | 1,042 | 182 | 41,262 / 59,301 | 1,335 | — |
| Full · RSA-2048 · X25519 | RUST | 1,062 | 100 % | 939 | 787 | 152 | 30,023 / 46,714 | 1,077 | — |

## Record layer — small keep-alive requests

64 keep-alive connections, `GET /1k` back to back, over TLS (AES-128-GCM) and over plaintext HTTP. *TLS overhead* is the TLS row's server CPU per request minus the plaintext row's: what the record layer costs per request-response pair.

| Server | transport | req/s | server util | CPU / req (µs) | p50 / p99 (µs) | TLS overhead / req (µs) |
|---|---|--:|--:|--:|--:|--:|
| NURL | TLS | 67,744 | 100 % | 14.7 | 940 / 1,020 | 1.76 |
| NURL | plaintext | 77,193 | 100 % | 12.9 | 831 / 916 |  |
| RUST | TLS | 68,410 | 100 % | 14.5 | 943 / 1,067 | 2.59 |
| RUST | plaintext | 83,562 | 100 % | 12.0 | 773 / 878 |  |

## Bulk — one connection, 1 MB bodies

One keep-alive connection downloading `/1m` back to back. *ns / KB* is server CPU per KiB delivered; the AEAD row of the primitive table is the floor a userspace record layer can reach. The kTLS row runs the NURL server with `NURL_KTLS=1`; *kTLS engaged* is the kernel's `TlsTxSw` counter over the cell — 0 means the kernel refused (no `tls` module) and the row is userspace again.

| Server | suite | MB/s | server util | server ns / KB | AEAD floor ns / KB | kTLS engaged |
|---|---|--:|--:|--:|--:|--:|
| NURL | aes128 | 1,287 | 60 % | 478 | 146 | — |
| NURL | chacha | 837 | 88 % | 1,083 | 584 | — |
| NURL | plain | 3,707 | 89 % | 246 | n/a | — |
| NURL | aes128+ktls | 763 | 53 % | 706 | 146 | yes |
| RUST | aes128 | 1,041 | 91 % | 892 | 275 | — |
| RUST | chacha | 877 | 94 % | 1,100 | 499 | — |
| RUST | plain | 3,728 | 88 % | 243 | n/a | — |

## Client — `packages/http-client` vs reqwest

Both single-threaded and sequential, both against the same Rust server, both offering their defaults (X25519MLKEM768 first). *full*: a new connection per request with resumption off (`http_client_set_resume F` / rustls `Resumption::disabled`), *resume*: a new connection per request offering the cached ticket, *ka*: one pooled keep-alive connection.

| Case | Client | req/s | MB/s | p50 / p99 (µs) | errors |
|---|---|--:|--:|--:|--:|
| full:/ | http-client | 1,521 | 0.02 | 653 / 728 | 0 |
| full:/ | reqwest | 1,130 | 0.02 | 867 / 1,161 | 0 |
| resume:/ | http-client | 1,566 | 0.02 | 633 / 715 | 0 |
| resume:/ | reqwest | 1,270 | 0.02 | 779 / 851 | 0 |
| ka:/1k | http-client | 19,478 | 19.9 | 50.0 / 67.0 | 0 |
| ka:/1k | reqwest | 14,433 | 14.8 | 66.0 / 88.0 | 0 |
| ka:/1m | http-client | 891 | 935 | 1,117 / 1,299 | 0 |
| ka:/1m | reqwest | 704 | 738 | 1,476 / 1,997 | 0 |

## Primitives — single core

Medians of 3 run(s), `bench_auto` discipline on both sides (ramp until a pass clears 50 ms). NURL is the pure-NURL stdlib; Rust is aws-lc-rs.

| Primitive | NURL µs/op | Rust µs/op | NURL / Rust speed |
|---|--:|--:|--:|
| X25519 keygen | 12.5 | 9.88 | 79 % |
| X25519 shared | 34.5 | 31.2 | 90 % |
| P-256 ECDH keygen | 18.2 | 11.4 | 63 % |
| P-256 ECDH shared | 87.4 | 56.9 | 65 % |
| ML-KEM-768 encaps | 20.3 | 16.0 | 79 % |
| ECDSA P-256 sign | 22.7 | 19.6 | 86 % |
| ECDSA P-256 verify | 102 | 64.4 | 63 % |
| RSA-2048 PSS sign | 993 | 741 | 75 % |
| HKDF-Expand-Label | 0.15 | 0.34 | 226 % |
| SHA-256 16 KB | 11.8 | 11.7 | 99 % |
| AES-128-GCM seal 16 KB | 2.33 | 4.41 | 189 % |
| ChaCha20-Poly1305 seal 16 KB | 9.35 | 7.99 | 85 % |

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | `AMD EPYC 9V74 80-Core Processor` |
| Logical cores | `4` |
| Server cores | `0-0` |
| Generator cores | `1-3` |
| Commit | `c4849a8f96d00ebe9b1484fb22bb5678ff647307` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40664985685 |
| NURL | `v0.79.1-33-gc4849a8f` |
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
