# NURL HTTP-server peer-comparison

Generated `2026-08-18T20:41:41Z` by `bench/run_http.sh`. **Do not edit by hand** — the next run overwrites it.

Each implementation accepts a TCP connection, parses one HTTP/1.1 request and writes a 14-byte `Hello, World!\n` body (`text/plain`), keep-alive. The TLS section runs the *same* servers and the same load over a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`. The NURL server is the `packages/http` HttpApp facade (`http_app_listen` / `http_app_listen_tls`) with a 10-thread worker pool — the surface a real NURL service deploys.

**Read the throughput columns, not the latency columns, at high concurrency.** These are *closed-loop* measurements: `oha` holds C connections open and fires the next request the instant one returns. When a server's in-flight work saturates below C (NURL's 10 blocking workers do, by design), the extra connections queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the few connections in flight. Such cells are marked ‡ and left un-bold: their latency is not a service-level number (that needs an open-loop generator — see *Planned rigor*). The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `1a7284a98ac03104f4e60939fc506b58ce21a089` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32183341356 |
| NURL | `v0.44.2-27-g1a7284a9` |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.2 |
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
| **req/s**    | NURL    | **14 602** | 73 630 | 72 381 | 74 412 |
|              | Rust    | 13 329 | **84 331** | **108 031** | **111 701** |
|              | Node    | 9 634 | 23 750 | 24 350 | 24 539 |
| **p50 (ms)** | NURL    | **0.06** | 0.13 | **0.13** | 0.13‡ |
|              | Rust    | 0.07 | **0.10** | 0.46 | **1.66** |
|              | Node    | 0.09 | 0.43 | 2.22 | 9.26 |
| **p99 (ms)** | NURL    | **0.09** | **0.24** | **0.27** | 0.26‡ |
|              | Rust    | **0.09** | 0.28 | 0.87 | **3.19** |
|              | Node    | 0.15 | 0.97 | 4.42 | 10.04 |

‡ closed-loop starved (NURL C=200: ~127.2 in flight).

## 2. TLS (HTTPS)

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **12 766** | 59 284 | 56 212 | 57 790 |
|              | Rust    | 11 928 | **63 116** | **85 632** | **89 982** |
|              | Node    | 8 305 | 20 183 | 19 950 | 20 440 |
| **p50 (ms)** | NURL    | **0.07** | 0.16 | **0.17** | 0.16‡ |
|              | Rust    | 0.08 | **0.14** | 0.57 | **2.04** |
|              | Node    | 0.11 | 0.41 | 2.04 | 8.43 |
| **p99 (ms)** | NURL    | **0.10** | **0.32** | **0.37** | 0.34‡ |
|              | Rust    | 0.11 | 0.35 | 1.12 | **4.06** |
|              | Node    | 0.16 | 0.77 | 3.57 | 13.96 |

‡ closed-loop starved (NURL C=200: ~124.2 in flight).

(Best per row in **bold**; latency winners are chosen only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server did not complete that cell.)

## 3. Connection-setup rate (new connection per request)

`--disable-keepalive`, so each request pays a fresh connection. For `http` that is the accept/teardown rate; for `https` it is **TLS handshakes per second** — the pure-NURL P-256 ECDHE + ECDSA-verify path (no OpenSSL, no AES-NI-tier handshake assembly) against rustls and Node. This is the cost a short-lived-connection edge deployment actually pays, and the one the keep-alive tables above amortise to nothing.

| Server | http conn/s | https handshakes/s |
|--------|------------:|-------------------:|
| NURL   | 925 | 3 113 |
| Rust   | **15 969** | **5 031** |
| Node   | 8 967 | 1 626 |

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
