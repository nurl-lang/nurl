# NURL HTTP-server peer-comparison

Generated `2026-09-03T09:48:47Z` by `bench/run_http.sh`. **Do not edit by hand** — the next run overwrites it.

Each implementation accepts a TCP connection, parses one HTTP/1.1 request and writes a 14-byte `Hello, World!\n` body (`text/plain`), keep-alive. The TLS section runs the *same* servers and the same load over a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`. The NURL server is the `packages/http` HttpApp facade (`http_app_listen` / `http_app_listen_tls`) in `http_app_async` mode — fiber per connection on the M:N async runtime, one worker pthread per core, the surface a scaling NURL service deploys (and the same model as the Rust peer's tokio multi-thread runtime).

**Read the throughput columns, not the latency columns, at high concurrency.** These are *closed-loop* measurements: `oha` holds C connections open and fires the next request the instant one returns. If a server's in-flight work saturates below C, the extra connections queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the few connections in flight. Such cells are marked ‡ and left un-bold: their latency is not a service-level number (that needs an open-loop generator — see *Planned rigor*). The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `cdd5b317376ef7fa7f153c44af8daa78577536c9` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33740536379 |
| NURL | `v0.59.0-3-gcdd5b317` |
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
| **req/s**    | NURL    | **25 299** | 79 434 | **110 673** | **113 655** |
|              | Rust    | 14 198 | **83 047** | 109 294 | 112 258 |
|              | Node    | 9 753 | 22 807 | 23 741 | 23 888 |
| **p50 (ms)** | NURL    | **0.03** | **0.11** | **0.44** | **1.63** |
|              | Rust    | 0.06 | **0.11** | 0.45 | 1.66 |
|              | Node    | 0.09 | 0.45 | 2.31 | 9.41 |
| **p99 (ms)** | NURL    | **0.07** | 0.30 | 1.17 | **3.16** |
|              | Rust    | 0.09 | **0.29** | **0.85** | 3.23 |
|              | Node    | 0.14 | 1.00 | 4.51 | 10.49 |

## 2. TLS (HTTPS)

|              | Server  | C = 1 | C = 10 | C = 50 | C = 200 |
|--------------|---------|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **18 694** | 58 553 | **87 575** | 87 806 |
|              | Rust    | 12 472 | **63 027** | 87 493 | **91 199** |
|              | Node    | 8 130 | 20 551 | 20 503 | 19 144 |
| **p50 (ms)** | NURL    | **0.04** | 0.15 | **0.53** | 2.06 |
|              | Rust    | 0.07 | **0.14** | 0.56 | **2.01** |
|              | Node    | 0.11 | 0.41 | 2.05 | 9.09 |
| **p99 (ms)** | NURL    | **0.09** | 0.42 | 2.31 | 4.79 |
|              | Rust    | 0.10 | **0.35** | **1.10** | **3.75** |
|              | Node    | 0.17 | 0.79 | 3.65 | 15.45 |

(Best per row in **bold**; latency winners are chosen only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server did not complete that cell.)

## 3. Connection-setup rate (new connection per request)

`--disable-keepalive`, so each request pays a fresh connection. For `http` that is the accept/teardown rate; for `https` it is **TLS handshakes per second** — the pure-NURL P-256 ECDHE + ECDSA-verify path (no OpenSSL, no AES-NI-tier handshake assembly) against rustls and Node. This is the cost a short-lived-connection edge deployment actually pays, and the one the keep-alive tables above amortise to nothing.

| Server | http conn/s | https handshakes/s |
|--------|------------:|-------------------:|
| NURL   | 16 057 | 4 980 |
| Rust   | **16 084** | **5 006** |
| Node   | 8 721 | 1 572 |

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
