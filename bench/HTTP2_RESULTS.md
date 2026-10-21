# NURL HTTP/2-server peer-comparison

Generated `2026-10-21T11:56:43Z` by `bench/run_http2.sh`. **Do not edit by hand** — the next run overwrites it.

The HTTP/2 companion of [`HTTP_RESULTS.md`](HTTP_RESULTS.md) (which stays HTTP/1.1-only). Each implementation accepts a connection, speaks HTTP/2 (RFC 9113 + HPACK, RFC 7541) and answers every request on every stream with the same 14-byte `Hello, World!\n` body (`text/plain`). Section 1 is cleartext HTTP/2 with prior knowledge (§3.4 — the `PRI * HTTP/2.0` preface, what `curl --http2-prior-knowledge`, `h2load` and `oha --http2` send); section 2 negotiates `h2` over ALPN (§3.3) on a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`.

The NURL server is `bench/http_server.nu` **unchanged from the HTTP/1.1 benchmark**: the `packages/http` HttpApp facade in `http_app_async` mode serves both protocols on every listener — ALPN decides over TLS, the connection preface decides on cleartext. The Rust peer drives hyper's `http2` connection builder on tokio (rustls with ALPN `h2` for TLS); the Node peer is the built-in `node:http2` module (`allowHTTP1: false` for TLS).

**Cells are `C x P`: C connections, each carrying P concurrent streams** (`oha --http2 -c C -p P`), so C x P requests are in flight. `1 x 100` is one connection multiplexing a hundred streams — HTTP/2's own axis, which HTTP/1.1 has no equivalent for; `50 x 1` is fifty connections with one stream each, the closest thing to the HTTP/1.1 `C = 50` cell.

**Read the throughput columns, not the latency columns, at high in-flight counts.** These are *closed-loop* measurements: `oha` fires the next request on a stream the instant the previous one returns. If a server's in-flight work saturates below C x P, the extra requests queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the requests in flight. Such cells are marked ‡ and left un-bold. The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `e8bc8d72c43b70c885d9f0a5bea1994649f810bd` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39595123659 |
| NURL | `v0.76.0-8-ge8bc8d72` |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
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
| **req/s**    | NURL    | **19 939** | **69 023** | **154 501** | 55 730 | **155 622** | 73 349 | **178 563** |
|              | Rust    | 13 681 | 58 196 | 112 827 | **56 007** | 134 391 | **79 714** | 143 012 |
|              | Node    | 8 844 | 35 606 | 61 823 | 17 120 | 48 698 | 17 181 | 45 029 |
| **p50 (ms)** | NURL    | **0.05** | **0.13** | **0.61** | **0.16** | **0.59** | 0.62 | **2.48** |
|              | Rust    | 0.06 | 0.16 | 0.78 | **0.16** | 0.66 | **0.61** | 3.43 |
|              | Node    | 0.10 | 0.26 | 1.43 | 0.58 | 1.71 | 2.70 | 11.26 |
| **p99 (ms)** | NURL    | **0.08** | **0.21** | **0.97** | 0.46 | 1.59 | 3.57 | 6.34 |
|              | Rust    | 0.12 | 0.26 | 1.15 | **0.40** | **1.45** | **1.21** | **6.29** |
|              | Node    | 0.18 | 0.38 | 3.76 | 1.30 | 4.98 | 4.32 | 21.45 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 19 939 | 27 091 | 0.74x | 0.05 | 0.03 |
| 10 | 55 730 | 76 885 | 0.72x | 0.16 | 0.11 |
| 50 | 73 349 | 110 232 | 0.67x | 0.62 | 0.42 |

## 2. HTTP/2 over TLS (ALPN h2)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **16 470** | 51 084 | **114 927** | 44 460 | **120 568** | 57 782 | **136 083** |
|              | Rust    | 11 726 | **51 740** | 111 191 | **44 918** | 117 113 | **65 533** | 124 908 |
|              | Node    | 7 578 | 33 014 | 59 852 | 14 225 | 44 392 | 14 630 | 41 835 |
| **p50 (ms)** | NURL    | **0.06** | **0.18** | **0.83** | **0.20** | **0.77** | 0.79 | **3.26** |
|              | Rust    | 0.07 | 0.19 | 0.85 | **0.20** | **0.77** | **0.74** | 3.95 |
|              | Node    | 0.12 | 0.27 | 1.49 | 0.61 | 1.93 | 2.95 | 11.52 |
| **p99 (ms)** | NURL    | **0.09** | 0.27 | 1.28 | 0.57 | 1.99 | 3.83 | 8.06 |
|              | Rust    | 0.13 | **0.26** | **1.06** | **0.46** | **1.65** | **1.48** | **6.84** |
|              | Node    | 0.20 | 0.42 | 4.85 | 1.07 | 4.43 | 4.81 | 24.59 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 16 470 | 21 861 | 0.75x | 0.06 | 0.04 |
| 10 | 44 460 | 62 414 | 0.71x | 0.20 | 0.14 |
| 50 | 57 782 | 82 425 | 0.70x | 0.79 | 0.56 |

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
