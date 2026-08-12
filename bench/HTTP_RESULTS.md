# NURL HTTP-server peer-comparison

Generated `2026-08-12T18:13:38Z` by `bench/run_http.sh`. **Do not edit by hand** — the next run overwrites it.

Each implementation accepts a TCP connection, parses one HTTP/1.1 request and writes a 14-byte `Hello, World!\n` body (`text/plain`), keep-alive. The TLS section runs the *same* servers and the same load over a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`. The NURL server is the `packages/http` HttpApp facade (`http_app_listen` / `http_app_listen_tls`) with a 10-thread worker pool — the surface a real NURL service deploys.

**Read the throughput columns, not the latency columns, at high concurrency.** These are *closed-loop* measurements: `oha` holds C connections open and fires the next request the instant one returns. When a server's in-flight work saturates below C (NURL's 10 blocking workers do, by design), the extra connections queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the few connections in flight. Such cells are marked ‡ and left un-bold: their latency is not a service-level number (that needs an open-loop generator — see *Planned rigor*). The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `Linux x86_64` |
| Kernel | `Linux 7.0.0-28-generic x86_64` |
| CPU | Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz (12 logical cores) |
| Memory | 32770952 KiB |
| Commit | `600939f970d4381e3934d94117513b8668a0541e` |
| NURL | `v0.39.0-9-gdf2f443-dirty` |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v24.15.0 |
| Load generator | oha 1.8.0 |

| Setting | Value |
|---|---|
| Throughput/latency | median of 3 x 10 s closed-loop runs, keep-alive |
| Concurrencies | 1 , 10 , 50 , 200 |
| Connection-setup rate | 20000 connections at c=20, `--disable-keepalive` |
| TLS cert | self-signed EC P-256, `CN=localhost` |

## 1. Plaintext HTTP

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **14 310** | **166 679** | 143 664 | 148 654 |
|              | Rust    | 13 303 | 148 512 | **210 527** | **293 300** |
|              | Node    | 8 390 | 26 724 | 28 003 | 27 236 |
| **p50 (ms)** | NURL    | **0.07** | **0.06** | **0.06** | 0.06‡ |
|              | Rust    | **0.07** | **0.06** | 0.20 | **0.63** |
|              | Node    | 0.12 | 0.32 | 1.66 | 7.37 |
| **p99 (ms)** | NURL    | **0.13** | **0.10** | **0.13** | 0.12‡ |
|              | Rust    | 0.15 | 0.13 | 0.73 | **1.65** |
|              | Node    | 0.19 | 0.75 | 3.60 | 14.26 |

‡ closed-loop starved (NURL C=200: ~132.3 in flight).

## 2. TLS (HTTPS)

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | 10 255 | **130 110** | 114 210 | 116 784 |
|              | Rust    | **10 803** | 121 890 | **172 426** | **227 575** |
|              | Node    | 8 759 | 19 667 | 20 372 | 19 131 |
| **p50 (ms)** | NURL    | **0.09** | **0.07** | **0.07** | 0.07‡ |
|              | Rust    | **0.09** | 0.08 | 0.25 | **0.82** |
|              | Node    | 0.10 | 0.45 | 2.35 | 10.08 |
| **p99 (ms)** | NURL    | 0.18 | **0.12** | **0.16** | 0.15‡ |
|              | Rust    | **0.17** | 0.16 | 0.85 | **2.05** |
|              | Node    | 0.21 | 0.99 | 3.05 | 13.09 |

‡ closed-loop starved (NURL C=200: ~130.8 in flight).

(Best per row in **bold**; latency winners are chosen only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server did not complete that cell.)

## 3. Connection-setup rate (new connection per request)

`--disable-keepalive`, so each request pays a fresh connection. For `http` that is the accept/teardown rate; for `https` it is **TLS handshakes per second** — the pure-NURL P-256 ECDHE + ECDSA-verify path (no OpenSSL, no AES-NI-tier handshake assembly) against rustls and Node. This is the cost a short-lived-connection edge deployment actually pays, and the one the keep-alive tables above amortise to nothing.

| Server | http conn/s | https handshakes/s |
|--------|------------:|-------------------:|
| NURL   | **54 948** | 2 470 |
| Rust   | 49 720 | **12 498** |
| Node   | 9 643 | 1 653 |

## Notes

- **What the TLS tables measure.** With keep-alive, a connection handshakes once and then serves many requests, so the section-2 gap to plaintext is the per-record AEAD, *not* the handshake. The handshake cost lives in section 3, where every request is a new connection.
- Rust serves TLS through `tokio-rustls`; Node through its built-in `https` module. Each uses its conventional stack, so the columns compare deployments, not just ciphers.
- Loopback only, HTTP/1.1 only, 14-byte body. No HTTP/2. Absolute numbers depend heavily on the host; compare columns within one run, not across machines.

### Planned rigor

Known limits of this harness, in priority order — each is a measurement this run does **not** yet make, called out so a reader does not have to guess:
1. **Open-loop latency.** Replace the closed-loop latency columns with a fixed-rate generator (`oha -q`, or `wrk2`/`vegeta`) at 50/80/95 % of each server's measured throughput, reporting p50/p99/p99.9/max. Closed loop cannot measure latency above capacity (coordinated omission), which is why saturated cells are marked ‡ rather than trusted.
2. **Core isolation.** Pin the server and the load generator to disjoint core sets (`taskset`) and equalise pool sizes, so `oha`'s threads do not compete with the server for CPU.
3. **CPU-time per request.** `getrusage(RUSAGE_SELF)` in each server → `(utime+stime)/requests`: the one figure immune to loopback, generator contention and pool size.
4. **Record-layer throughput.** Re-run TLS with 16 KB and 1 MB bodies; a 14-byte body exercises the handshake and framing, not the AEAD stream.
