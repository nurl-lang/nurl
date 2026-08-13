# NURL HTTP-server peer-comparison

Generated `2026-08-13T03:19:00Z` by `bench/run_http.sh`. **Do not edit by hand** — the next run overwrites it.

Each implementation accepts a TCP connection, parses one HTTP/1.1 request and writes a 14-byte `Hello, World!\n` body (`text/plain`), keep-alive. The TLS section runs the *same* servers and the same load over a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`. The NURL server is the `packages/http` HttpApp facade (`http_app_listen` / `http_app_listen_tls`) with a 10-thread worker pool — the surface a real NURL service deploys.

**Read the throughput columns, not the latency columns, at high concurrency.** These are *closed-loop* measurements: `oha` holds C connections open and fires the next request the instant one returns. When a server's in-flight work saturates below C (NURL's 10 blocking workers do, by design), the extra connections queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the few connections in flight. Such cells are marked ‡ and left un-bold: their latency is not a service-level number (that needs an open-loop generator — see *Planned rigor*). The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `741bdce07463e6cb017897f5cda68e2d9884cfe2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31663384471 |
| NURL | `v0.39.0-21-g741bdce0` |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.1 |
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
| **req/s**    | NURL    | **27 306** | 116 352 | 112 642 | 111 859 |
|              | Rust    | 25 823 | **118 625** | **140 524** | **143 715** |
|              | Node    | 19 088 | 51 725 | 52 512 | 51 319 |
| **p50 (ms)** | NURL    | **0.03** | **0.08** | **0.08** | 0.08‡ |
|              | Rust    | 0.04 | **0.08** | 0.36 | **1.30** |
|              | Node    | 0.05 | 0.15 | 0.76 | 3.39 |
| **p99 (ms)** | NURL    | **0.05** | **0.16** | **0.18** | 0.19‡ |
|              | Rust    | **0.05** | **0.16** | 0.64 | **2.52** |
|              | Node    | 0.09 | 0.50 | 1.59 | 5.75 |

‡ closed-loop starved (NURL C=200: ~132.0 in flight).

## 2. TLS (HTTPS)

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | 23 018 | 94 252 | 83 396 | 88 659 |
|              | Rust    | **23 418** | **103 292** | **118 172** | **117 336** |
|              | Node    | 15 266 | 37 057 | 45 588 | 33 984 |
| **p50 (ms)** | NURL    | **0.04** | 0.10 | **0.11** | 0.10‡ |
|              | Rust    | **0.04** | **0.09** | 0.41 | **1.57** |
|              | Node    | 0.06 | 0.29 | 1.00 | 4.93 |
| **p99 (ms)** | NURL    | **0.06** | 0.24 | **0.27** | 0.25‡ |
|              | Rust    | **0.06** | **0.20** | 0.78 | **3.06** |
|              | Node    | 0.11 | 0.43 | 1.84 | 9.16 |

‡ closed-loop starved (NURL C=200: ~129.4 in flight).

(Best per row in **bold**; latency winners are chosen only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server did not complete that cell.)

## 3. Connection-setup rate (new connection per request)

`--disable-keepalive`, so each request pays a fresh connection. For `http` that is the accept/teardown rate; for `https` it is **TLS handshakes per second** — the pure-NURL P-256 ECDHE + ECDSA-verify path (no OpenSSL, no AES-NI-tier handshake assembly) against rustls and Node. This is the cost a short-lived-connection edge deployment actually pays, and the one the keep-alive tables above amortise to nothing.

| Server | http conn/s | https handshakes/s |
|--------|------------:|-------------------:|
| NURL   | **25 072** | 3 411 |
| Rust   | 23 731 | **6 869** |
| Node   | 12 485 | 2 015 |

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
