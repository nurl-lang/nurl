# NURL HTTP/2-server peer-comparison

Generated `2026-09-11T20:33:45Z` by `bench/run_http2.sh`. **Do not edit by hand** — the next run overwrites it.

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
| Commit | `e61a52d1a7b14ead80b25ed4c298634ef674754c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34644528041 |
| NURL | `v0.63.0-10-ge61a52d1` |
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
| **req/s**    | NURL    | **17 171** | **82 080** | 81 498 | 55 981 | 94 998 | 79 712 | 131 682 |
|              | Rust    | 11 193 | 52 612 | **112 864** | **57 642** | **133 554** | **81 037** | **144 909** |
|              | Node    | 7 786 | 33 986 | 63 349 | 18 077 | 51 360 | 19 176 | 48 588 |
| **p50 (ms)** | NURL    | **0.05** | **0.12** | 1.21 | 0.16 | **0.21** | **0.58** | **3.19** |
|              | Rust    | 0.08 | 0.18 | **0.77** | **0.15** | 0.66 | 0.61 | 3.38 |
|              | Node    | 0.11 | 0.26 | 1.42 | 0.56 | 1.55 | 2.17 | 9.13 |
| **p99 (ms)** | NURL    | **0.09** | **0.18** | 2.23 | 0.45 | 19.04 | 3.24 | 10.48 |
|              | Rust    | 0.11 | 0.28 | **1.13** | **0.40** | **1.48** | **1.16** | **6.25** |
|              | Node    | 0.17 | 0.38 | 3.71 | 1.28 | 4.97 | 4.12 | 22.82 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 17 171 | 23 554 | 0.73x | 0.05 | 0.03 |
| 10 | 55 981 | 75 830 | 0.74x | 0.16 | 0.11 |
| 50 | 79 712 | 107 306 | 0.74x | 0.58 | 0.43 |

## 2. HTTP/2 over TLS (ALPN h2)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **14 234** | **65 316** | 66 425 | 43 455 | 73 759 | 62 300 | 103 436 |
|              | Rust    | 9 957 | 48 341 | **110 870** | **46 651** | **118 070** | **68 298** | **129 212** |
|              | Node    | 6 634 | 31 269 | 61 683 | 15 114 | 46 659 | 14 331 | 40 154 |
| **p50 (ms)** | NURL    | **0.06** | **0.15** | 1.50 | 0.20 | **0.29** | 0.73 | 4.53 |
|              | Rust    | 0.09 | 0.20 | **0.84** | **0.19** | 0.75 | **0.71** | **3.81** |
|              | Node    | 0.13 | 0.29 | 1.47 | 0.57 | 1.89 | 3.23 | 11.39 |
| **p99 (ms)** | NURL    | **0.11** | **0.20** | 1.63 | 0.58 | 27.53 | 3.75 | 15.21 |
|              | Rust    | 0.13 | 0.31 | **1.13** | **0.46** | **1.65** | **1.41** | **6.83** |
|              | Node    | 0.19 | 0.40 | 3.86 | 1.02 | 4.61 | 4.73 | 27.36 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 14 234 | 17 075 | 0.83x | 0.06 | 0.05 |
| 10 | 43 455 | 54 834 | 0.79x | 0.20 | 0.16 |
| 50 | 62 300 | 80 899 | 0.77x | 0.73 | 0.56 |

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
