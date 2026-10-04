# NURL HTTP/2-server peer-comparison

Generated `2026-10-04T20:11:29Z` by `bench/run_http2.sh`. **Do not edit by hand** — the next run overwrites it.

The HTTP/2 companion of [`HTTP_RESULTS.md`](HTTP_RESULTS.md) (which stays HTTP/1.1-only). Each implementation accepts a connection, speaks HTTP/2 (RFC 9113 + HPACK, RFC 7541) and answers every request on every stream with the same 14-byte `Hello, World!\n` body (`text/plain`). Section 1 is cleartext HTTP/2 with prior knowledge (§3.4 — the `PRI * HTTP/2.0` preface, what `curl --http2-prior-knowledge`, `h2load` and `oha --http2` send); section 2 negotiates `h2` over ALPN (§3.3) on a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`.

The NURL server is `bench/http_server.nu` **unchanged from the HTTP/1.1 benchmark**: the `packages/http` HttpApp facade in `http_app_async` mode serves both protocols on every listener — ALPN decides over TLS, the connection preface decides on cleartext. The Rust peer drives hyper's `http2` connection builder on tokio (rustls with ALPN `h2` for TLS); the Node peer is the built-in `node:http2` module (`allowHTTP1: false` for TLS).

**Cells are `C x P`: C connections, each carrying P concurrent streams** (`oha --http2 -c C -p P`), so C x P requests are in flight. `1 x 100` is one connection multiplexing a hundred streams — HTTP/2's own axis, which HTTP/1.1 has no equivalent for; `50 x 1` is fifty connections with one stream each, the closest thing to the HTTP/1.1 `C = 50` cell.

**Read the throughput columns, not the latency columns, at high in-flight counts.** These are *closed-loop* measurements: `oha` fires the next request on a stream the instant the previous one returns. If a server's in-flight work saturates below C x P, the extra requests queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the requests in flight. Such cells are marked ‡ and left un-bold. The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `f7fb2d1a362d8631839c5055fc16fcef912bb289` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37230925920 |
| NURL | `v0.70.0-3-gf7fb2d1a` |
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
| **req/s**    | NURL    | **29 643** | **93 591** | **194 894** | 82 056 | **215 211** | **110 171** | **247 291** |
|              | Rust    | 21 284 | 83 666 | 151 331 | **92 117** | 195 086 | 109 682 | 205 200 |
|              | Node    | 13 738 | 53 332 | 88 826 | 35 826 | 75 501 | 36 671 | 69 039 |
| **p50 (ms)** | NURL    | **0.03** | **0.10** | **0.50** | **0.10** | **0.42** | **0.42** | **1.77** |
|              | Rust    | 0.04 | 0.11 | 0.56 | **0.10** | 0.44 | 0.45 | 2.36 |
|              | Node    | 0.06 | 0.16 | 0.99 | 0.22 | 1.02 | 1.10 | 6.39 |
| **p99 (ms)** | NURL    | **0.05** | **0.14** | **0.69** | 0.32 | 1.15 | 1.91 | 4.66 |
|              | Rust    | 0.07 | 0.18 | 0.78 | **0.23** | **1.00** | **0.82** | **4.63** |
|              | Node    | 0.11 | 0.25 | 2.94 | 0.71 | 3.71 | 2.25 | 18.10 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 29 643 | 37 842 | 0.78x | 0.03 | 0.02 |
| 10 | 82 056 | 118 543 | 0.69x | 0.10 | 0.07 |
| 50 | 110 171 | 153 768 | 0.72x | 0.42 | 0.31 |

## 2. HTTP/2 over TLS (ALPN h2)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **25 133** | 70 006 | 140 641 | 66 805 | 164 422 | 90 090 | **189 069** |
|              | Rust    | 19 016 | **81 920** | **150 005** | **76 364** | **173 129** | **96 296** | 182 521 |
|              | Node    | 12 058 | 49 197 | 86 853 | 30 652 | 70 894 | 29 370 | 62 674 |
| **p50 (ms)** | NURL    | **0.04** | 0.13 | 0.69 | 0.13 | 0.56 | **0.50** | **2.33** |
|              | Rust    | 0.05 | **0.12** | **0.61** | **0.11** | **0.51** | 0.51 | 2.66 |
|              | Node    | 0.07 | 0.18 | 1.02 | 0.27 | 1.20 | 1.42 | 7.14 |
| **p99 (ms)** | NURL    | **0.06** | 0.20 | 0.94 | 0.41 | 1.51 | 2.62 | 5.83 |
|              | Rust    | 0.08 | **0.19** | **0.75** | **0.29** | **1.13** | **0.96** | **5.17** |
|              | Node    | 0.13 | 0.27 | 3.18 | 0.57 | 3.35 | 2.81 | 18.66 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 25 133 | 31 565 | 0.80x | 0.04 | 0.03 |
| 10 | 66 805 | 90 712 | 0.74x | 0.13 | 0.09 |
| 50 | 90 090 | 120 231 | 0.75x | 0.50 | 0.39 |

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
