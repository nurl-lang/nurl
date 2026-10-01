# NURL HTTP/2-server peer-comparison

Generated `2026-10-01T19:10:05Z` by `bench/run_http2.sh`. **Do not edit by hand** — the next run overwrites it.

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
| Commit | `97f7a6df0346d785f83d644f66c5dd4323f7e65a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/36911810178 |
| NURL | `v0.68.0-4-g97f7a6df` |
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
| **req/s**    | NURL    | **16 187** | **64 142** | **145 164** | 51 180 | **147 669** | 72 341 | **177 133** |
|              | Rust    | 11 150 | 53 681 | 111 025 | **56 636** | 134 891 | **81 166** | 147 025 |
|              | Node    | 7 683 | 34 981 | 62 273 | 17 905 | 50 908 | 17 887 | 49 603 |
| **p50 (ms)** | NURL    | **0.05** | **0.15** | **0.67** | 0.17 | **0.62** | 0.63 | **2.49** |
|              | Rust    | 0.08 | 0.18 | 0.77 | **0.16** | 0.65 | **0.61** | 3.34 |
|              | Node    | 0.11 | 0.25 | 1.45 | 0.56 | 1.58 | 2.37 | 8.90 |
| **p99 (ms)** | NURL    | **0.10** | **0.22** | **1.02** | 0.52 | 1.69 | 3.56 | 6.25 |
|              | Rust    | 0.11 | 0.28 | 1.11 | **0.40** | **1.46** | **1.16** | **6.16** |
|              | Node    | 0.18 | 0.38 | 3.44 | 1.28 | 4.89 | 4.31 | 20.15 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 16 187 | 23 387 | 0.69x | 0.05 | 0.03 |
| 10 | 51 180 | 74 748 | 0.68x | 0.17 | 0.12 |
| 50 | 72 341 | 112 484 | 0.64x | 0.63 | 0.42 |

## 2. HTTP/2 over TLS (ALPN h2)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **13 237** | **49 136** | 99 731 | 40 801 | 110 145 | 58 783 | **129 381** |
|              | Rust    | 9 950 | 48 812 | **112 265** | **46 352** | **118 055** | **67 869** | 128 989 |
|              | Node    | 6 825 | 31 833 | 61 949 | 14 995 | 48 094 | 14 305 | 42 759 |
| **p50 (ms)** | NURL    | **0.07** | **0.19** | 0.97 | 0.22 | 0.84 | 0.77 | **3.58** |
|              | Rust    | 0.09 | 0.20 | **0.83** | **0.19** | **0.75** | **0.72** | 3.82 |
|              | Node    | 0.13 | 0.28 | 1.48 | 0.57 | 1.86 | 3.15 | 10.59 |
| **p99 (ms)** | NURL    | **0.12** | **0.27** | 1.43 | 0.62 | 2.22 | 3.40 | 8.49 |
|              | Rust    | 0.13 | 0.30 | **1.13** | **0.47** | **1.66** | **1.44** | **6.84** |
|              | Node    | 0.20 | 0.42 | 4.46 | 1.06 | 4.21 | 4.75 | 22.87 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 13 237 | 17 243 | 0.77x | 0.07 | 0.05 |
| 10 | 40 801 | 57 029 | 0.72x | 0.22 | 0.15 |
| 50 | 58 783 | 79 788 | 0.74x | 0.77 | 0.57 |

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
