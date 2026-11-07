# NURL HTTP/2-server peer-comparison

Generated `2026-11-07T06:17:39Z` by `bench/run_http2.sh`. **Do not edit by hand** — the next run overwrites it.

The HTTP/2 companion of [`HTTP_RESULTS.md`](HTTP_RESULTS.md) (which stays HTTP/1.1-only). Each implementation accepts a connection, speaks HTTP/2 (RFC 9113 + HPACK, RFC 7541) and answers every request on every stream with the same 14-byte `Hello, World!\n` body (`text/plain`). Section 1 is cleartext HTTP/2 with prior knowledge (§3.4 — the `PRI * HTTP/2.0` preface, what `curl --http2-prior-knowledge`, `h2load` and `oha --http2` send); section 2 negotiates `h2` over ALPN (§3.3) on a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`.

The NURL server is `bench/http_server.nu` **unchanged from the HTTP/1.1 benchmark**: the `packages/http` HttpApp facade in `http_app_async` mode serves both protocols on every listener — ALPN decides over TLS, the connection preface decides on cleartext. The Rust peer drives hyper's `http2` connection builder on tokio (rustls with ALPN `h2` for TLS); the Node peer is the built-in `node:http2` module (`allowHTTP1: false` for TLS).

**Cells are `C x P`: C connections, each carrying P concurrent streams** (`oha --http2 -c C -p P`), so C x P requests are in flight. `1 x 100` is one connection multiplexing a hundred streams — HTTP/2's own axis, which HTTP/1.1 has no equivalent for; `50 x 1` is fifty connections with one stream each, the closest thing to the HTTP/1.1 `C = 50` cell.

**Read the throughput columns, not the latency columns, at high in-flight counts.** These are *closed-loop* measurements: `oha` fires the next request on a stream the instant the previous one returns. If a server's in-flight work saturates below C x P, the extra requests queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the requests in flight. Such cells are marked ‡ and left un-bold. The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `5ab35366b67fb4619867e1a648b2b02711a093b3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42345973795 |
| NURL | `v0.90.0` |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.2 |
| Load generator | oha 1.8.0 |

| Setting | Value |
|---|---|
| Throughput/latency | median of 3 x 10 s closed-loop runs |
| Cells (C x P) | 1x1 , 1x10 , 1x100 , 10x1 , 10x10 , 50x1 , 50x10 |
| TLS cert | self-signed EC P-256, `CN=localhost`, ALPN `h2` |

## 1. Cleartext HTTP/2 (h2c, prior knowledge)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **13 401** | **67 427** | **166 880** | **60 141** | **189 032** | **82 904** | **205 315** |
|              | Rust    | 13 051 | 59 772 | 109 826 | 56 181 | 137 587 | 79 666 | 146 446 |
|              | Node    | 8 898 | 39 696 | 73 058 | 18 693 | 56 093 | 19 468 | 53 865 |
| **p50 (ms)** | NURL    | **0.07** | **0.14** | **0.55** | **0.15** | **0.48** | **0.52** | **2.18** |
|              | Rust    | **0.07** | 0.16 | 0.77 | 0.16 | 0.65 | 0.61 | 3.34 |
|              | Node    | 0.10 | 0.23 | 1.25 | 0.54 | 1.40 | 2.19 | 7.79 |
| **p99 (ms)** | NURL    | **0.11** | **0.19** | **0.90** | 0.41 | **1.32** | 3.50 | **5.68** |
|              | Rust    | **0.11** | 0.25 | 1.17 | **0.39** | 1.42 | **1.21** | 6.13 |
|              | Node    | 0.16 | 0.32 | 6.03 | 1.20 | 5.70 | 3.61 | 19.55 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 13 401 | 17 368 | 0.77x | 0.07 | 0.05 |
| 10 | 60 141 | 88 688 | 0.68x | 0.15 | 0.10 |
| 50 | 82 904 | 108 435 | 0.76x | 0.52 | 0.44 |

## 2. HTTP/2 over TLS (ALPN h2)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **12 305** | **56 807** | **142 019** | **51 961** | **159 647** | 68 111 | **171 279** |
|              | Rust    | 11 337 | 53 833 | 113 633 | 45 575 | 120 852 | **68 207** | 132 349 |
|              | Node    | 7 869 | 36 458 | 68 413 | 15 884 | 49 450 | 15 758 | 47 325 |
| **p50 (ms)** | NURL    | **0.07** | **0.17** | **0.67** | **0.18** | **0.57** | **0.70** | **2.62** |
|              | Rust    | 0.08 | 0.18 | 0.82 | 0.20 | 0.74 | 0.71 | 3.74 |
|              | Node    | 0.11 | 0.25 | 1.32 | 0.53 | 1.72 | 2.70 | 9.16 |
| **p99 (ms)** | NURL    | **0.12** | **0.22** | **1.05** | **0.41** | **1.52** | 1.96 | **6.63** |
|              | Rust    | 0.13 | 0.24 | 1.12 | 0.46 | 1.63 | **1.43** | 6.66 |
|              | Node    | 0.18 | 0.35 | 5.96 | 1.42 | 7.11 | 4.28 | 22.80 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 12 305 | 15 422 | 0.80x | 0.07 | 0.06 |
| 10 | 51 961 | 71 048 | 0.73x | 0.18 | 0.13 |
| 50 | 68 111 | 86 771 | 0.78x | 0.70 | 0.57 |

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
