# NURL HTTP-server peer-comparison

Generated `2026-08-13T11:14:44Z` by `bench/run_http.sh`. **Do not edit by hand** — the next run overwrites it.

Each implementation accepts a TCP connection, parses one HTTP/1.1 request and writes a 14-byte `Hello, World!\n` body (`text/plain`), keep-alive. The TLS section runs the *same* servers and the same load over a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`. The NURL server is the `packages/http` HttpApp facade (`http_app_listen` / `http_app_listen_tls`) with a 10-thread worker pool — the surface a real NURL service deploys.

**Read the throughput columns, not the latency columns, at high concurrency.** These are *closed-loop* measurements: `oha` holds C connections open and fires the next request the instant one returns. When a server's in-flight work saturates below C (NURL's 10 blocking workers do, by design), the extra connections queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the few connections in flight. Such cells are marked ‡ and left un-bold: their latency is not a service-level number (that needs an open-loop generator — see *Planned rigor*). The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `25f11434db56ee8640d1dfe04de97a849a3505dd` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31694389865 |
| NURL | `v0.39.0-42-g25f11434` |
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
| **req/s**    | NURL    | **24 437** | 113 767 | 104 869 | 113 615 |
|              | Rust    | 23 329 | **122 894** | **146 896** | **143 578** |
|              | Node    | 17 837 | 44 292 | 46 363 | 39 575 |
| **p50 (ms)** | NURL    | **0.04** | 0.08 | **0.09** | 0.08‡ |
|              | Rust    | **0.04** | **0.07** | 0.34 | **1.29** |
|              | Node    | 0.05 | 0.21 | 0.94 | 4.39 |
| **p99 (ms)** | NURL    | **0.06** | 0.19 | **0.19** | 0.17‡ |
|              | Rust    | **0.06** | **0.18** | 0.66 | **2.45** |
|              | Node    | 0.09 | 0.53 | 1.84 | 6.92 |

‡ closed-loop starved (NURL C=200: ~131.8 in flight).

## 2. TLS (HTTPS)

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | 20 473 | 90 873 | 82 642 | 87 698 |
|              | Rust    | **20 585** | **95 843** | **111 796** | **110 068** |
|              | Node    | 14 575 | 33 215 | 32 827 | 27 518 |
| **p50 (ms)** | NURL    | 0.05 | 0.10 | **0.11** | 0.10‡ |
|              | Rust    | **0.04** | **0.09** | 0.46 | **1.68** |
|              | Node    | 0.06 | 0.27 | 1.34 | 6.47 |
| **p99 (ms)** | NURL    | **0.07** | 0.24 | **0.25** | 0.25‡ |
|              | Rust    | **0.07** | **0.22** | 0.85 | **3.11** |
|              | Node    | 0.11 | 0.47 | 2.19 | 9.88 |

‡ closed-loop starved (NURL C=200: ~129.8 in flight).

(Best per row in **bold**; latency winners are chosen only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server did not complete that cell.)

## 3. Connection-setup rate (new connection per request)

`--disable-keepalive`, so each request pays a fresh connection. For `http` that is the accept/teardown rate; for `https` it is **TLS handshakes per second** — the pure-NURL P-256 ECDHE + ECDSA-verify path (no OpenSSL, no AES-NI-tier handshake assembly) against rustls and Node. This is the cost a short-lived-connection edge deployment actually pays, and the one the keep-alive tables above amortise to nothing.

| Server | http conn/s | https handshakes/s |
|--------|------------:|-------------------:|
| NURL   | **28 491** | 3 483 |
| Rust   | 28 165 | **6 216** |
| Node   | 16 181 | 1 758 |

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
