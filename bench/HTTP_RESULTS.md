# NURL HTTP-server peer-comparison

Generated `2026-10-06T04:09:34Z` by `bench/run_http.sh`. **Do not edit by hand** — the next run overwrites it.

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
| Commit | `0ae00340604700fba67fd8e9fd5309e85da8fa82` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37412013843 |
| NURL | `v0.70.0-12-g0ae00340` |
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
| Machine load | 1.87 at start (quiet) |

## 1. Plaintext HTTP

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **28 681** | 98 088 | 117 382 | **120 699** |
|              | Rust    | 15 183 | **98 795** | **118 072** | 118 427 |
|              | Node    | 10 861 | 32 339 | 32 948 | 30 572 |
| **p50 (ms)** | NURL    | **0.03** | **0.10** | **0.45** | **1.52** |
|              | Rust    | 0.06 | **0.10** | **0.45** | 1.57 |
|              | Node    | 0.09 | 0.26 | 1.47 | 6.49 |
| **p99 (ms)** | NURL    | **0.06** | 0.16 | 0.63 | 2.40 |
|              | Rust    | 0.08 | **0.15** | **0.55** | **2.12** |
|              | Node    | 0.12 | 0.58 | 2.95 | 7.46 |
| **CPU us/req** | NURL    | 34.85 | 17.69 | 16.07 | 15.88 |
|              | Rust    | **28.00** | **17.00** | **15.30** | **14.91** |
|              | Node    | 60.99 | 30.96 | 30.43 | 32.83 |

## 2. TLS (HTTPS)

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **20 978** | 77 142 | 93 142 | 93 728 |
|              | Rust    | 13 624 | **78 581** | **93 529** | **96 265** |
|              | Node    | 9 276 | 24 270 | 24 724 | 23 531 |
| **p50 (ms)** | NURL    | **0.05** | **0.12** | **0.56** | 1.94 |
|              | Rust    | 0.07 | **0.12** | 0.57 | **1.91** |
|              | Node    | 0.11 | 0.39 | 1.98 | 8.24 |
| **p99 (ms)** | NURL    | **0.07** | 0.24 | 0.88 | 3.34 |
|              | Rust    | 0.09 | **0.18** | **0.71** | **2.56** |
|              | Node    | 0.14 | 0.78 | 2.50 | 9.56 |
| **CPU us/req** | NURL    | 47.28 | 22.85 | 20.78 | 20.98 |
|              | Rust    | **30.04** | **20.36** | **18.23** | **17.04** |
|              | Node    | 79.57 | 41.22 | 40.62 | 42.92 |

(Best per row in **bold**; latency winners are chosen only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server did not complete that cell.)

## 3. Connection-setup rate (new connection per request)

`--disable-keepalive`, so each request pays a fresh connection. For `http` that is the accept/teardown rate; for `https` it is **TLS handshakes per second** — the pure-NURL P-256 ECDHE + ECDSA-verify path (no OpenSSL, no AES-NI-tier handshake assembly) against rustls and Node. This is the cost a short-lived-connection edge deployment actually pays, and the one the keep-alive tables above amortise to nothing.

| Server | http conn/s | https handshakes/s |
|--------|------------:|-------------------:|
| NURL   | **17 622** | 5 533 |
| Rust   | 17 602 | **5 582** |
| Node   | 9 715 | 1 724 |

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
