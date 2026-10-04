# NURL HTTP-server peer-comparison

Generated `2026-10-04T18:05:18Z` by `bench/run_http.sh`. **Do not edit by hand** — the next run overwrites it.

Each implementation accepts a TCP connection, parses one HTTP/1.1 request and writes a 14-byte `Hello, World!\n` body (`text/plain`), keep-alive. The TLS section runs the *same* servers and the same load over a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`. The NURL server is the `packages/http` HttpApp facade (`http_app_listen` / `http_app_listen_tls`) in `http_app_async` mode — fiber per connection on the M:N async runtime, one worker pthread per core, the surface a scaling NURL service deploys (and the same model as the Rust peer's tokio multi-thread runtime).

**Read the throughput columns, not the latency columns, at high concurrency.** These are *closed-loop* measurements: `oha` holds C connections open and fires the next request the instant one returns. If a server's in-flight work saturates below C, the extra connections queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the few connections in flight. Such cells are marked ‡ and left un-bold: their latency is not a service-level number (that needs an open-loop generator — see *Planned rigor*). The effective in-flight count is `req/s x mean-latency` (Little's law).

**The `CPU us/req` row is the one to compare across peers.** It is server CPU time (`utime+stime` over every thread, read externally from `/proc/<pid>/stat` around the measured window) divided by the exact number of responses — so unlike `req/s` it does not move when the generator pushes harder or softer. Two warnings that cost real time to learn: it rises with worker count for **every** runtime (~30 % from 1 to 4 workers here), and an unpinned run inflates it because the generator is stealing the server's cores. Comparing a figure taken at one worker count against a figure taken at another manufactures a peer gap out of nothing but concurrency. The Environment block above states both, for exactly that reason.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `255fdfe9083140904143f3dc86ec267c5ffdc03d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37222730970 |
| NURL | `v0.70.0-1-g255fdfe9` |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |
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
| Machine load | 1.92 at start (quiet) |

## 1. Plaintext HTTP

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **28 926** | **99 096** | 117 999 | **122 078** |
|              | Rust    | 15 418 | 98 678 | **119 616** | 121 559 |
|              | Node    | 10 939 | 32 976 | 33 115 | 32 565 |
| **p50 (ms)** | NURL    | **0.03** | **0.10** | **0.45** | **1.51** |
|              | Rust    | 0.06 | **0.10** | **0.45** | 1.52 |
|              | Node    | 0.09 | 0.26 | 1.46 | 6.09 |
| **p99 (ms)** | NURL    | **0.06** | 0.16 | 0.61 | 2.18 |
|              | Rust    | 0.10 | **0.15** | **0.54** | **2.08** |
|              | Node    | 0.13 | 0.56 | 2.92 | 6.91 |
| **CPU us/req** | NURL    | 34.38 | 17.82 | 16.15 | 15.92 |
|              | Rust    | **26.87** | **17.02** | **15.24** | **14.84** |
|              | Node    | 60.54 | 30.40 | 30.14 | 30.91 |

## 2. TLS (HTTPS)

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **20 832** | 77 896 | **94 524** | 94 082 |
|              | Rust    | 13 672 | **78 034** | 93 972 | **96 298** |
|              | Node    | 9 285 | 23 856 | 24 059 | 22 925 |
| **p50 (ms)** | NURL    | **0.05** | **0.12** | **0.53** | 2.09 |
|              | Rust    | 0.07 | **0.12** | 0.57 | **1.92** |
|              | Node    | 0.10 | 0.40 | 2.05 | 8.41 |
| **p99 (ms)** | NURL    | **0.07** | 0.23 | 0.86 | 3.28 |
|              | Rust    | 0.11 | **0.18** | **0.73** | **2.60** |
|              | Node    | 0.15 | 0.79 | 2.54 | 10.13 |
| **CPU us/req** | NURL    | 47.86 | 23.03 | 20.77 | 21.00 |
|              | Rust    | **29.09** | **20.26** | **18.05** | **16.85** |
|              | Node    | 79.65 | 41.88 | 41.41 | 44.21 |

(Best per row in **bold**; latency winners are chosen only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server did not complete that cell.)

## 3. Connection-setup rate (new connection per request)

`--disable-keepalive`, so each request pays a fresh connection. For `http` that is the accept/teardown rate; for `https` it is **TLS handshakes per second** — the pure-NURL P-256 ECDHE + ECDSA-verify path (no OpenSSL, no AES-NI-tier handshake assembly) against rustls and Node. This is the cost a short-lived-connection edge deployment actually pays, and the one the keep-alive tables above amortise to nothing.

| Server | http conn/s | https handshakes/s |
|--------|------------:|-------------------:|
| NURL   | 17 975 | **5 562** |
| Rust   | **18 135** | 5 545 |
| Node   | 9 957 | 1 714 |

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
