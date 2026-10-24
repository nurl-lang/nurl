# NURL HTTP-server peer-comparison

Generated `2026-10-24T10:03:27Z` by `bench/run_http.sh`. **Do not edit by hand** — the next run overwrites it.

Each implementation accepts a TCP connection, parses one HTTP/1.1 request and writes a 14-byte `Hello, World!\n` body (`text/plain`), keep-alive. The TLS section runs the *same* servers and the same load over a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`. The NURL server is the `packages/http` HttpApp facade (`http_app_listen` / `http_app_listen_tls`) in `http_app_async` mode — fiber per connection on the M:N async runtime, one worker pthread per core, the surface a scaling NURL service deploys (and the same model as the Rust peer's tokio multi-thread runtime).

**Read the throughput columns, not the latency columns, at high concurrency.** These are *closed-loop* measurements: `oha` holds C connections open and fires the next request the instant one returns. If a server's in-flight work saturates below C, the extra connections queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the few connections in flight. Such cells are marked ‡ and left un-bold: their latency is not a service-level number (that needs an open-loop generator — see *Planned rigor*). The effective in-flight count is `req/s x mean-latency` (Little's law).

**The `CPU us/req` row is the one to compare across peers.** It is server CPU time (`utime+stime` over every thread, read externally from `/proc/<pid>/stat` around the measured window) divided by the exact number of responses — so unlike `req/s` it does not move when the generator pushes harder or softer. Two warnings that cost real time to learn: it rises with worker count for **every** runtime (~30 % from 1 to 4 workers here), and an unpinned run inflates it because the generator is stealing the server's cores. Comparing a figure taken at one worker count against a figure taken at another manufactures a peer gap out of nothing but concurrency. The Environment block above states both, for exactly that reason.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373444 KiB |
| Commit | `eb911f28b35a5457c1c82a25c7891bf53727823b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40084069068 |
| NURL | `v0.77.2-39-geb911f28` |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v22.23.3 |
| Load generator | oha 1.8.0 |

| Setting | Value |
|---|---|
| Throughput/latency | median of 3 x 10 s closed-loop runs, keep-alive |
| Concurrencies | 1 , 10 , 50 , 200 |
| Connection-setup rate | 20000 connections at c=20, `--disable-keepalive` |
| TLS cert | self-signed EC P-256, `CN=localhost` |
| Core isolation | server on cores `0-1`, generator on cores `2-3` (`taskset`) |
| Worker threads | 2 per server (`NURL_WORKERS` / `TOKIO_WORKER_THREADS`); Node's server is single-threaded |
| Machine load | 1.81 at start (quiet) |

## 1. Plaintext HTTP

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **29 222** | **98 991** | 117 486 | **118 858** |
|              | Rust    | 15 760 | 98 344 | **118 272** | 117 402 |
|              | Node    | 11 117 | 31 971 | 32 453 | 30 448 |
| **p50 (ms)** | NURL    | **0.03** | **0.10** | **0.45** | **1.55** |
|              | Rust    | 0.06 | **0.10** | **0.45** | 1.58 |
|              | Node    | 0.09 | 0.27 | 1.50 | 6.48 |
| **p99 (ms)** | NURL    | **0.05** | 0.16 | 0.56 | **2.14** |
|              | Rust    | 0.07 | **0.15** | **0.55** | 2.21 |
|              | Node    | 0.12 | 0.59 | 3.00 | 7.57 |
| **CPU us/req** | NURL    | 34.32 | **16.22** | 15.55 | 15.38 |
|              | Rust    | **26.81** | 17.07 | **15.36** | **14.97** |
|              | Node    | 61.33 | 31.34 | 30.98 | 33.14 |

## 2. TLS (HTTPS)

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **25 729** | 78 033 | 92 015 | 93 510 |
|              | Rust    | 13 900 | **78 681** | **93 434** | **95 132** |
|              | Node    | 9 242 | 24 704 | 24 604 | 21 548 |
| **p50 (ms)** | NURL    | **0.04** | **0.12** | **0.56** | 1.98 |
|              | Rust    | 0.07 | **0.12** | 0.58 | **1.94** |
|              | Node    | 0.11 | 0.38 | 1.99 | 9.01 |
| **p99 (ms)** | NURL    | **0.06** | **0.19** | 0.75 | 2.83 |
|              | Rust    | 0.09 | **0.19** | **0.72** | **2.65** |
|              | Node    | 0.14 | 0.77 | 2.66 | 11.52 |
| **CPU us/req** | NURL    | 39.06 | **16.33** | **17.13** | **17.10** |
|              | Rust    | **29.63** | 20.40 | 18.07 | 17.29 |
|              | Node    | 80.22 | 40.55 | 40.47 | 47.40 |

(Best per row in **bold**; latency winners are chosen only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server did not complete that cell.)

## 3. Connection-setup rate (new connection per request)

`--disable-keepalive`, so each request pays a fresh connection. For `http` that is the accept/teardown rate; for `https` it is **TLS handshakes per second** — the pure-NURL P-256 ECDHE + ECDSA-verify path (no OpenSSL, no AES-NI-tier handshake assembly) against rustls and Node. This is the cost a short-lived-connection edge deployment actually pays, and the one the keep-alive tables above amortise to nothing.

| Server | http conn/s | https handshakes/s |
|--------|------------:|-------------------:|
| NURL   | **18 009** | **6 893** |
| Rust   | 17 705 | 5 529 |
| Node   | 9 354 | 1 712 |

## Notes

- **What the TLS tables measure.** With keep-alive, a connection handshakes once and then serves many requests, so the section-2 gap to plaintext is the per-record AEAD, *not* the handshake. The handshake cost lives in section 3, where every request is a new connection.
- Rust serves TLS through `tokio-rustls`; Node through its built-in `https` module. Each uses its conventional stack, so the columns compare deployments, not just ciphers.
- Loopback only, HTTP/1.1 only, 14-byte body. No HTTP/2. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.

### Planned rigor

Known limits of this harness, in priority order — each is a measurement this run does **not** yet make, called out so a reader does not have to guess:
1. **Open-loop latency.** Replace the closed-loop latency columns with a fixed-rate generator (`oha -q`, or `wrk2`/`vegeta`) at 50/80/95 % of each server's measured throughput, reporting p50/p99/p99.9/max. Closed loop cannot measure latency above capacity (coordinated omission), which is why saturated cells are marked ‡ rather than trusted.
2. ~~**Core isolation.**~~ **Done** — the server and the generator run on disjoint core sets via `taskset` and every runtime that sizes a pool from `nproc` is given the same worker count. See the Environment block; a run on fewer than 4 cores, or without `taskset`, says so there instead.
3. ~~**CPU-time per request.**~~ **Done**, and without the `getrusage` call the original plan wanted in each server: `utime+stime` read externally from `/proc/<pid>/stat` is the same figure and needs no code change in any peer, so NURL, Rust and Node are all measured the same way. Divided by the exact response count from oha's status-code histogram, never by `rps x duration`.
4. **Record-layer throughput.** Re-run TLS with 16 KB and 1 MB bodies; a 14-byte body exercises the handshake and framing, not the AEAD stream.
