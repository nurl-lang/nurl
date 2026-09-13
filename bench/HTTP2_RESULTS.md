# NURL HTTP/2-server peer-comparison

Generated `2026-09-13T20:59:24Z` by `bench/run_http2.sh`. **Do not edit by hand** — the next run overwrites it.

The HTTP/2 companion of [`HTTP_RESULTS.md`](HTTP_RESULTS.md) (which stays HTTP/1.1-only). Each implementation accepts a connection, speaks HTTP/2 (RFC 9113 + HPACK, RFC 7541) and answers every request on every stream with the same 14-byte `Hello, World!\n` body (`text/plain`). Section 1 is cleartext HTTP/2 with prior knowledge (§3.4 — the `PRI * HTTP/2.0` preface, what `curl --http2-prior-knowledge`, `h2load` and `oha --http2` send); section 2 negotiates `h2` over ALPN (§3.3) on a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`.

The NURL server is `bench/http_server.nu` **unchanged from the HTTP/1.1 benchmark**: the `packages/http` HttpApp facade in `http_app_async` mode serves both protocols on every listener — ALPN decides over TLS, the connection preface decides on cleartext. The Rust peer drives hyper's `http2` connection builder on tokio (rustls with ALPN `h2` for TLS); the Node peer is the built-in `node:http2` module (`allowHTTP1: false` for TLS).

**Cells are `C x P`: C connections, each carrying P concurrent streams** (`oha --http2 -c C -p P`), so C x P requests are in flight. `1 x 100` is one connection multiplexing a hundred streams — HTTP/2's own axis, which HTTP/1.1 has no equivalent for; `50 x 1` is fifty connections with one stream each, the closest thing to the HTTP/1.1 `C = 50` cell.

**Read the throughput columns, not the latency columns, at high in-flight counts.** These are *closed-loop* measurements: `oha` fires the next request on a stream the instant the previous one returns. If a server's in-flight work saturates below C x P, the extra requests queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the requests in flight. Such cells are marked ‡ and left un-bold. The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `a7146d7d90a106a97e8b205454fdeb42f572cf4d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34782256483 |
| NURL | `v0.65.0-4-ga7146d7d` |
| Rust | rustc 1.98.1 (48a229cea 2026-09-01) |
| Node | v22.23.2 |
| Load generator | oha 1.8.0 |

| Setting | Value |
|---|---|
| Throughput/latency | median of 3 x 10 s closed-loop runs |
| Cells (C x P) | 1x1 , 1x10 , 1x100 , 10x1 , 10x10 , 50x1 , 50x10 |
| TLS cert | self-signed EC P-256, `CN=localhost`, ALPN `h2` |

## 1. Cleartext HTTP/2 (h2c, prior knowledge)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **15 734** | **60 389** | **130 084** | 51 724 | **139 424** | 73 351 | **166 230** |
|              | Rust    | 11 087 | 53 428 | 110 631 | **58 290** | 134 832 | **81 966** | 148 030 |
|              | Node    | 7 739 | 34 868 | 65 521 | 19 016 | 53 127 | 19 016 | 52 440 |
| **p50 (ms)** | NURL    | **0.06** | **0.16** | **0.74** | 0.17 | 0.66 | 0.62 | **2.68** |
|              | Rust    | 0.08 | 0.18 | 0.78 | **0.15** | **0.65** | **0.60** | 3.29 |
|              | Node    | 0.11 | 0.27 | 1.37 | 0.41 | 1.51 | 2.12 | 8.49 |
| **p99 (ms)** | NURL    | **0.10** | **0.22** | **1.11** | 0.50 | 1.79 | 2.51 | 6.57 |
|              | Rust    | 0.11 | 0.28 | 1.14 | **0.40** | **1.48** | **1.16** | **6.19** |
|              | Node    | 0.17 | 0.37 | 3.44 | 1.24 | 4.57 | 4.08 | 19.79 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 15 734 | 23 088 | 0.68x | 0.06 | 0.03 |
| 10 | 51 724 | 73 452 | 0.70x | 0.17 | 0.12 |
| 50 | 73 351 | 110 127 | 0.67x | 0.62 | 0.42 |

## 2. HTTP/2 over TLS (ALPN h2)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **13 193** | 46 431 | 87 059 | 40 452 | 104 701 | 55 490 | 121 535 |
|              | Rust    | 10 023 | **49 207** | **112 652** | **46 184** | **118 925** | **70 023** | **131 219** |
|              | Node    | 6 935 | 31 837 | 62 520 | 15 818 | 48 688 | 14 663 | 46 127 |
| **p50 (ms)** | NURL    | **0.07** | 0.21 | 1.11 | 0.22 | 0.88 | 0.79 | 4.09 |
|              | Rust    | 0.09 | **0.20** | **0.85** | **0.19** | **0.75** | **0.69** | **3.76** |
|              | Node    | 0.13 | 0.28 | 1.46 | 0.55 | 1.84 | 2.93 | 9.70 |
| **p99 (ms)** | NURL    | **0.11** | **0.29** | 1.57 | 0.64 | 2.48 | 3.31 | 8.62 |
|              | Rust    | 0.13 | 0.30 | **1.07** | **0.46** | **1.64** | **1.39** | **6.68** |
|              | Node    | 0.19 | 0.40 | 4.07 | 1.04 | 4.03 | 4.59 | 22.92 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 13 193 | 17 464 | 0.76x | 0.07 | 0.05 |
| 10 | 40 452 | 55 741 | 0.73x | 0.22 | 0.15 |
| 50 | 55 490 | 79 453 | 0.70x | 0.79 | 0.57 |

(Best per column in **bold**; latency winners are chosen only among non-starved cells. ‡ = closed-loop starved. `n/a` = tool absent; `FAIL` = the server did not complete that cell.)

## Notes

- **No connection-setup-rate table here.** `oha --disable-keepalive` has no effect on its HTTP/2 client (it keeps the C connections and reuses them), so the per-connection cost cannot be measured with this generator. The TLS handshake is protocol-independent; its rate is in `HTTP_RESULTS.md` §3. What HTTP/2 adds on top of it is one SETTINGS exchange per connection.
- Rust serves TLS through `tokio-rustls` (ALPN `h2`); Node through `http2.createSecureServer`. Each uses its conventional stack, so the columns compare deployments, not just ciphers.
- HTTP/2 conformance is not this report's job: `tools/h2spec_gate.sh` runs h2spec (146/146, strict 147/147) against the same NURL HttpApp in CI. A fast server that fails h2spec would not be listed as a win.
- Loopback only, 14-byte body. Absolute numbers depend heavily on the host; compare columns within one run, not across machines, and compare against `HTTP_RESULTS.md` only when both were produced on the same runner class.

### Planned rigor

1. **Open-loop latency.** A fixed-rate generator (`oha -q --latency-correction --http2`) at 50/80/95 % of each server's measured throughput, reporting p50/p99/p99.9 — the `bench/http_torture` treatment, for HTTP/2.
2. **Realistic bodies.** 1 KB / 16 KB / 1 MB responses, where DATA framing, flow-control windows and the per-stream WINDOW_UPDATE traffic start to matter; a 14-byte body measures HEADERS + HPACK.
3. **Core isolation** (server and generator on disjoint cores) and **CPU-time per request**, as in the torture harness.
