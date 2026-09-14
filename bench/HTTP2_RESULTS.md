# NURL HTTP/2-server peer-comparison

Generated `2026-09-14T03:51:06Z` by `bench/run_http2.sh`. **Do not edit by hand** — the next run overwrites it.

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
| Commit | `079fb775b6a998d2e5b1dbe9fb09d8e1cc213768` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34803799886 |
| NURL | `v0.65.0-10-g079fb775` |
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
| **req/s**    | NURL    | **15 619** | **61 009** | **128 125** | 50 067 | **138 085** | 75 617 | **165 450** |
|              | Rust    | 10 750 | 53 055 | 115 069 | **58 143** | 135 290 | **82 358** | 147 523 |
|              | Node    | 7 421 | 34 012 | 65 305 | 18 920 | 52 255 | 18 761 | 50 401 |
| **p50 (ms)** | NURL    | **0.06** | **0.16** | **0.76** | 0.18 | 0.66 | 0.61 | **2.75** |
|              | Rust    | 0.08 | 0.18 | 0.78 | **0.15** | **0.65** | **0.60** | 3.31 |
|              | Node    | 0.12 | 0.27 | 1.39 | 0.42 | 1.54 | 2.21 | 8.68 |
| **p99 (ms)** | NURL    | **0.10** | **0.22** | **1.13** | 0.51 | 1.86 | 2.55 | 6.63 |
|              | Rust    | 0.12 | 0.28 | **1.13** | **0.40** | **1.46** | **1.16** | **6.09** |
|              | Node    | 0.17 | 0.37 | 3.40 | 1.29 | 4.78 | 4.32 | 19.20 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 15 619 | 23 988 | 0.65x | 0.06 | 0.03 |
| 10 | 50 067 | 72 666 | 0.69x | 0.18 | 0.12 |
| 50 | 75 617 | 106 946 | 0.71x | 0.61 | 0.43 |

## 2. HTTP/2 over TLS (ALPN h2)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **12 612** | 45 919 | 87 002 | 39 473 | 102 896 | 54 497 | 120 288 |
|              | Rust    | 9 628 | **48 251** | **115 745** | **45 483** | **118 922** | **67 804** | **129 621** |
|              | Node    | 6 652 | 32 105 | 63 870 | 15 410 | 49 752 | 14 897 | 45 938 |
| **p50 (ms)** | NURL    | **0.07** | 0.21 | 1.13 | 0.22 | 0.89 | 0.81 | 4.14 |
|              | Rust    | 0.09 | **0.20** | **0.84** | **0.20** | **0.75** | **0.72** | **3.80** |
|              | Node    | 0.13 | 0.28 | 1.43 | 0.55 | 1.79 | 2.82 | 9.74 |
| **p99 (ms)** | NURL    | **0.12** | **0.29** | 1.58 | 0.65 | 2.54 | 3.16 | 8.80 |
|              | Rust    | 0.13 | 0.31 | **1.05** | **0.47** | **1.63** | **1.43** | **6.84** |
|              | Node    | 0.19 | 0.39 | 3.72 | 1.03 | 4.13 | 4.63 | 22.59 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 12 612 | 16 527 | 0.76x | 0.07 | 0.05 |
| 10 | 39 473 | 54 317 | 0.73x | 0.22 | 0.16 |
| 50 | 54 497 | 79 286 | 0.69x | 0.81 | 0.57 |

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
