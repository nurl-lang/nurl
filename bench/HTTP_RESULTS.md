# NURL HTTP-server peer-comparison

Generated `2026-08-24T20:15:59Z` by `bench/run_http.sh`. **Do not edit by hand** — the next run overwrites it.

Each implementation accepts a TCP connection, parses one HTTP/1.1 request and writes a 14-byte `Hello, World!\n` body (`text/plain`), keep-alive. The TLS section runs the *same* servers and the same load over a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`. The NURL server is the `packages/http` HttpApp facade (`http_app_listen` / `http_app_listen_tls`) in `http_app_async` mode — fiber per connection on the M:N async runtime, one worker pthread per core, the surface a scaling NURL service deploys (and the same model as the Rust peer's tokio multi-thread runtime).

**Read the throughput columns, not the latency columns, at high concurrency.** These are *closed-loop* measurements: `oha` holds C connections open and fires the next request the instant one returns. If a server's in-flight work saturates below C, the extra connections queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the few connections in flight. Such cells are marked ‡ and left un-bold: their latency is not a service-level number (that needs an open-loop generator — see *Planned rigor*). The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `5bbbcf512ce887bc3b5b84fb90716d2f2f0a63b8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32772614125 |
| NURL | `v0.50.0-29-g5bbbcf51` |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |
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
| **req/s**    | NURL    | **39 771** | 83 480 | 124 631 | 117 424 |
|              | Rust    | 25 514 | **128 435** | **144 338** | **151 432** |
|              | Node    | FAIL | FAIL | FAIL | FAIL |
| **p50 (ms)** | NURL    | **0.02** | 0.11 | 0.37 | 1.46 |
|              | Rust    | 0.04 | **0.07** | **0.35** | **1.22** |
|              | Node    | FAIL | FAIL | FAIL | FAIL |
| **p99 (ms)** | NURL    | **0.04** | 0.25 | 0.83 | 3.41 |
|              | Rust    | 0.05 | **0.16** | **0.63** | **2.31** |
|              | Node    | FAIL | FAIL | FAIL | FAIL |

## 2. TLS (HTTPS)

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **33 504** | 68 685 | 99 365 | 95 862 |
|              | Rust    | 23 338 | **104 800** | **122 256** | **126 237** |
|              | Node    | 15 318 | 39 000 | 41 340 | 40 608 |
| **p50 (ms)** | NURL    | **0.03** | 0.14 | 0.46 | 1.77 |
|              | Rust    | 0.04 | **0.09** | **0.40** | **1.46** |
|              | Node    | 0.06 | 0.20 | 1.00 | 4.23 |
| **p99 (ms)** | NURL    | **0.04** | 0.35 | 1.12 | 4.36 |
|              | Rust    | 0.06 | **0.20** | **0.75** | **2.83** |
|              | Node    | 0.11 | 0.43 | 1.84 | 7.87 |

(Best per row in **bold**; latency winners are chosen only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server did not complete that cell.)

## 3. Connection-setup rate (new connection per request)

`--disable-keepalive`, so each request pays a fresh connection. For `http` that is the accept/teardown rate; for `https` it is **TLS handshakes per second** — the pure-NURL P-256 ECDHE + ECDSA-verify path (no OpenSSL, no AES-NI-tier handshake assembly) against rustls and Node. This is the cost a short-lived-connection edge deployment actually pays, and the one the keep-alive tables above amortise to nothing.

| Server | http conn/s | https handshakes/s |
|--------|------------:|-------------------:|
| NURL   | **25 687** | 5 536 |
| Rust   | 24 523 | **6 903** |
| Node   | FAIL | 2 156 |

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
