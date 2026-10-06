# NURL HTTP/2-server peer-comparison

Generated `2026-10-06T04:07:59Z` by `bench/run_http2.sh`. **Do not edit by hand** — the next run overwrites it.

The HTTP/2 companion of [`HTTP_RESULTS.md`](HTTP_RESULTS.md) (which stays HTTP/1.1-only). Each implementation accepts a connection, speaks HTTP/2 (RFC 9113 + HPACK, RFC 7541) and answers every request on every stream with the same 14-byte `Hello, World!\n` body (`text/plain`). Section 1 is cleartext HTTP/2 with prior knowledge (§3.4 — the `PRI * HTTP/2.0` preface, what `curl --http2-prior-knowledge`, `h2load` and `oha --http2` send); section 2 negotiates `h2` over ALPN (§3.3) on a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`.

The NURL server is `bench/http_server.nu` **unchanged from the HTTP/1.1 benchmark**: the `packages/http` HttpApp facade in `http_app_async` mode serves both protocols on every listener — ALPN decides over TLS, the connection preface decides on cleartext. The Rust peer drives hyper's `http2` connection builder on tokio (rustls with ALPN `h2` for TLS); the Node peer is the built-in `node:http2` module (`allowHTTP1: false` for TLS).

**Cells are `C x P`: C connections, each carrying P concurrent streams** (`oha --http2 -c C -p P`), so C x P requests are in flight. `1 x 100` is one connection multiplexing a hundred streams — HTTP/2's own axis, which HTTP/1.1 has no equivalent for; `50 x 1` is fifty connections with one stream each, the closest thing to the HTTP/1.1 `C = 50` cell.

**Read the throughput columns, not the latency columns, at high in-flight counts.** These are *closed-loop* measurements: `oha` fires the next request on a stream the instant the previous one returns. If a server's in-flight work saturates below C x P, the extra requests queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the requests in flight. Such cells are marked ‡ and left un-bold. The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `0ae00340604700fba67fd8e9fd5309e85da8fa82` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37412038521 |
| NURL | `v0.70.0-12-g0ae00340` |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |
| Node | v22.23.3 |
| Load generator | oha 1.8.0 |

| Setting | Value |
|---|---|
| Throughput/latency | median of 3 x 10 s closed-loop runs |
| Cells (C x P) | 1x1 , 1x10 , 1x100 , 10x1 , 10x10 , 50x1 , 50x10 |
| TLS cert | self-signed EC P-256, `CN=localhost`, ALPN `h2` |

## 1. Cleartext HTTP/2 (h2c, prior knowledge)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **39 819** | **127 876** | **265 403** | **116 587** | **298 186** | **144 910** | **336 062** |
|              | Rust    | 28 441 | 120 624 | 158 825 | 116 228 | 241 954 | 140 110 | 283 306 |
|              | Node    | 23 519 | 76 181 | 119 145 | 57 572 | 103 177 | 53 396 | 99 772 |
| **p50 (ms)** | NURL    | **0.02** | 0.08 | **0.36** | **0.07** | **0.30** | **0.32** | **1.31** |
|              | Rust    | 0.03 | **0.07** | 0.39 | 0.09 | 0.31 | 0.35 | 1.68 |
|              | Node    | 0.04 | 0.12 | 0.72 | 0.15 | 0.76 | 0.83 | 4.62 |
| **p99 (ms)** | NURL    | **0.03** | **0.10** | **0.53** | 0.25 | 0.87 | 1.14 | **3.35** |
|              | Rust    | 0.04 | 0.11 | 0.68 | **0.16** | **0.72** | **0.62** | 3.44 |
|              | Node    | 0.06 | 0.29 | 2.40 | 0.38 | 2.94 | 1.38 | 13.25 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 39 819 | 44 562 | 0.89x | 0.02 | 0.02 |
| 10 | 116 587 | 149 623 | 0.78x | 0.07 | 0.06 |
| 50 | 144 910 | 195 804 | 0.74x | 0.32 | 0.24 |

## 2. HTTP/2 over TLS (ALPN h2)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **31 748** | 86 911 | 171 084 | 85 468 | 208 123 | 104 563 | 235 387 |
|              | Rust    | 26 440 | **105 559** | **198 792** | **107 229** | **232 545** | **125 648** | **259 859** |
|              | Node    | 22 533 | 74 058 | 123 001 | 51 806 | 103 908 | 48 519 | 96 092 |
| **p50 (ms)** | NURL    | **0.03** | 0.11 | 0.57 | 0.10 | 0.43 | 0.43 | 1.99 |
|              | Rust    | 0.04 | **0.08** | **0.43** | **0.09** | **0.34** | **0.39** | **1.84** |
|              | Node    | 0.04 | 0.12 | 0.71 | 0.17 | 0.82 | 0.91 | 5.02 |
| **p99 (ms)** | NURL    | **0.04** | 0.14 | 0.77 | 0.32 | 1.23 | 1.24 | 4.65 |
|              | Rust    | 0.05 | **0.13** | **0.64** | **0.19** | **0.76** | **0.73** | **3.71** |
|              | Node    | 0.06 | 0.27 | 3.06 | 0.30 | 2.75 | 1.51 | 13.79 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 31 748 | 37 943 | 0.84x | 0.03 | 0.02 |
| 10 | 85 468 | 119 913 | 0.71x | 0.10 | 0.07 |
| 50 | 104 563 | 150 631 | 0.69x | 0.43 | 0.30 |

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
