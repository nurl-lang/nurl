# NURL HTTP/2-server peer-comparison

Generated `2026-10-22T06:05:07Z` by `bench/run_http2.sh`. **Do not edit by hand** — the next run overwrites it.

The HTTP/2 companion of [`HTTP_RESULTS.md`](HTTP_RESULTS.md) (which stays HTTP/1.1-only). Each implementation accepts a connection, speaks HTTP/2 (RFC 9113 + HPACK, RFC 7541) and answers every request on every stream with the same 14-byte `Hello, World!\n` body (`text/plain`). Section 1 is cleartext HTTP/2 with prior knowledge (§3.4 — the `PRI * HTTP/2.0` preface, what `curl --http2-prior-knowledge`, `h2load` and `oha --http2` send); section 2 negotiates `h2` over ALPN (§3.3) on a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`.

The NURL server is `bench/http_server.nu` **unchanged from the HTTP/1.1 benchmark**: the `packages/http` HttpApp facade in `http_app_async` mode serves both protocols on every listener — ALPN decides over TLS, the connection preface decides on cleartext. The Rust peer drives hyper's `http2` connection builder on tokio (rustls with ALPN `h2` for TLS); the Node peer is the built-in `node:http2` module (`allowHTTP1: false` for TLS).

**Cells are `C x P`: C connections, each carrying P concurrent streams** (`oha --http2 -c C -p P`), so C x P requests are in flight. `1 x 100` is one connection multiplexing a hundred streams — HTTP/2's own axis, which HTTP/1.1 has no equivalent for; `50 x 1` is fifty connections with one stream each, the closest thing to the HTTP/1.1 `C = 50` cell.

**Read the throughput columns, not the latency columns, at high in-flight counts.** These are *closed-loop* measurements: `oha` fires the next request on a stream the instant the previous one returns. If a server's in-flight work saturates below C x P, the extra requests queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the requests in flight. Such cells are marked ‡ and left un-bold. The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `4cc2a80a00753b0ab965b79977e142b17d2cf2e9` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39731307771 |
| NURL | `v0.76.0-32-g4cc2a80a` |
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
| **req/s**    | NURL    | 18 512 | 70 215 | **157 821** | 68 801 | **174 203** | **86 954** | **201 519** |
|              | Rust    | **18 815** | **71 606** | 124 479 | **70 008** | 154 495 | 84 863 | 163 056 |
|              | Node    | 11 605 | 41 417 | 69 211 | 28 921 | 56 644 | 27 589 | 55 741 |
| **p50 (ms)** | NURL    | **0.05** | 0.14 | **0.61** | **0.12** | **0.52** | **0.52** | **2.19** |
|              | Rust    | **0.05** | **0.13** | 0.71 | 0.13 | 0.57 | 0.58 | 3.00 |
|              | Node    | 0.07 | 0.21 | 1.27 | 0.26 | 1.61 | 1.46 | 9.00 |
| **p99 (ms)** | NURL    | **0.08** | **0.18** | **0.90** | 0.43 | 1.49 | 3.05 | **5.64** |
|              | Rust    | **0.08** | 0.21 | 1.00 | **0.31** | **1.28** | **1.13** | 5.65 |
|              | Node    | 0.14 | 0.32 | 3.37 | 0.92 | 4.40 | 2.85 | 18.87 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 18 512 | 23 460 | 0.79x | 0.05 | 0.04 |
| 10 | 68 801 | 96 138 | 0.72x | 0.12 | 0.09 |
| 50 | 86 954 | 118 140 | 0.74x | 0.52 | 0.41 |

## 2. HTTP/2 over TLS (ALPN h2)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | 16 402 | 58 841 | **128 567** | **59 709** | **148 123** | **77 055** | **170 748** |
|              | Rust    | **17 156** | **67 294** | 121 963 | 57 370 | 136 668 | 74 426 | 146 401 |
|              | Node    | 10 157 | 37 000 | 66 038 | 21 648 | 56 046 | 22 183 | 48 997 |
| **p50 (ms)** | NURL    | **0.05** | 0.16 | **0.75** | **0.15** | **0.61** | **0.57** | **2.59** |
|              | Rust    | **0.05** | **0.14** | 0.76 | 0.16 | 0.66 | 0.68 | 3.35 |
|              | Node    | 0.08 | 0.24 | 1.33 | 0.37 | 1.55 | 1.89 | 10.11 |
| **p99 (ms)** | NURL    | **0.09** | 0.22 | 1.08 | 0.47 | 1.70 | 3.54 | 6.68 |
|              | Rust    | 0.10 | **0.21** | **0.90** | **0.36** | **1.43** | **1.23** | **6.06** |
|              | Node    | 0.17 | 0.35 | 3.81 | 0.73 | 3.86 | 3.59 | 21.33 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 16 402 | 21 670 | 0.76x | 0.05 | 0.04 |
| 10 | 59 709 | 86 310 | 0.69x | 0.15 | 0.11 |
| 50 | 77 055 | 93 559 | 0.82x | 0.57 | 0.52 |

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
