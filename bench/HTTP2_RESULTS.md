# NURL HTTP/2-server peer-comparison

Generated `2026-09-02T19:14:30Z` by `bench/run_http2.sh`. **Do not edit by hand** — the next run overwrites it.

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
| Commit | `a50e7ddc877bc1fa31d104a95f177b4158354823` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33671875805 |
| NURL | `v0.58.0-16-ga50e7ddc` |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |
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
| **req/s**    | NURL    | **44 765** | **151 114** | 149 422 | **142 278** | 196 403 | **163 451** | 264 332 |
|              | Rust    | 30 437 | 123 214 | **164 646** | 126 184 | **258 185** | 145 380 | **298 565** |
|              | Node    | 25 864 | 84 768 | 131 988 | 62 539 | 115 110 | 62 153 | 112 541 |
| **p50 (ms)** | NURL    | **0.02** | **0.07** | 0.66 | **0.06** | **0.08** | **0.29** | **1.35** |
|              | Rust    | 0.03 | **0.07** | **0.37** | 0.08 | 0.28 | 0.34 | 1.59 |
|              | Node    | 0.04 | 0.11 | 0.66 | 0.15 | 0.68 | 0.72 | 3.94 |
| **p99 (ms)** | NURL    | **0.03** | **0.08** | 0.79 | 0.19 | 3.10 | 0.72 | 8.42 |
|              | Rust    | 0.04 | 0.11 | **0.64** | **0.14** | **0.67** | **0.59** | **3.28** |
|              | Node    | 0.05 | 0.15 | 2.05 | 0.34 | 2.66 | 1.14 | 11.41 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 44 765 | 49 568 | 0.90x | 0.02 | 0.02 |
| 10 | 142 278 | 168 855 | 0.84x | 0.06 | 0.05 |
| 50 | 163 451 | 208 109 | 0.79x | 0.29 | 0.23 |

## 2. HTTP/2 over TLS (ALPN h2)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **40 357** | **134 506** | 135 318 | **124 259** | 170 915 | **147 892** | 235 057 |
|              | Rust    | 29 286 | 120 435 | **215 926** | 115 234 | **248 775** | 134 849 | **274 634** |
|              | Node    | 24 315 | 79 820 | 130 510 | 55 331 | 110 659 | 52 334 | 99 730 |
| **p50 (ms)** | NURL    | **0.02** | **0.07** | 0.74 | **0.07** | **0.09** | **0.32** | **1.49** |
|              | Rust    | 0.03 | **0.07** | **0.40** | 0.08 | 0.32 | 0.37 | 1.74 |
|              | Node    | 0.04 | 0.11 | 0.67 | 0.16 | 0.77 | 0.85 | 4.87 |
| **p99 (ms)** | NURL    | **0.03** | **0.09** | 0.77 | 0.24 | 3.11 | 0.89 | 11.09 |
|              | Rust    | 0.04 | 0.12 | **0.56** | **0.17** | **0.71** | **0.68** | **3.50** |
|              | Node    | 0.06 | 0.16 | 2.58 | 0.25 | 2.54 | 1.34 | 12.90 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 40 357 | 43 174 | 0.93x | 0.02 | 0.02 |
| 10 | 124 259 | 133 141 | 0.93x | 0.07 | 0.06 |
| 50 | 147 892 | 174 659 | 0.85x | 0.32 | 0.27 |

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
