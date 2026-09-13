# NURL HTTP/2-server peer-comparison

Generated `2026-09-13T12:30:54Z` by `bench/run_http2.sh`. **Do not edit by hand** — the next run overwrites it.

The HTTP/2 companion of [`HTTP_RESULTS.md`](HTTP_RESULTS.md) (which stays HTTP/1.1-only). Each implementation accepts a connection, speaks HTTP/2 (RFC 9113 + HPACK, RFC 7541) and answers every request on every stream with the same 14-byte `Hello, World!\n` body (`text/plain`). Section 1 is cleartext HTTP/2 with prior knowledge (§3.4 — the `PRI * HTTP/2.0` preface, what `curl --http2-prior-knowledge`, `h2load` and `oha --http2` send); section 2 negotiates `h2` over ALPN (§3.3) on a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`.

The NURL server is `bench/http_server.nu` **unchanged from the HTTP/1.1 benchmark**: the `packages/http` HttpApp facade in `http_app_async` mode serves both protocols on every listener — ALPN decides over TLS, the connection preface decides on cleartext. The Rust peer drives hyper's `http2` connection builder on tokio (rustls with ALPN `h2` for TLS); the Node peer is the built-in `node:http2` module (`allowHTTP1: false` for TLS).

**Cells are `C x P`: C connections, each carrying P concurrent streams** (`oha --http2 -c C -p P`), so C x P requests are in flight. `1 x 100` is one connection multiplexing a hundred streams — HTTP/2's own axis, which HTTP/1.1 has no equivalent for; `50 x 1` is fifty connections with one stream each, the closest thing to the HTTP/1.1 `C = 50` cell.

**Read the throughput columns, not the latency columns, at high in-flight counts.** These are *closed-loop* measurements: `oha` fires the next request on a stream the instant the previous one returns. If a server's in-flight work saturates below C x P, the extra requests queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the requests in flight. Such cells are marked ‡ and left un-bold. The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `54427430972b8aa2ca36fb27d435daaacd09dca7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34757130236 |
| NURL | `v0.64.0-3-g54427430` |
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
| **req/s**    | NURL    | **24 194** | 65 562 | 66 589 | 60 443 | 81 438 | 73 224 | 111 755 |
|              | Rust    | 18 956 | **66 822** | **141 219** | **83 213** | **172 210** | **106 180** | **181 076** |
|              | Node    | 13 505 | 45 000 | 63 869 | 30 267 | 56 905 | 29 923 | 56 175 |
| **p50 (ms)** | NURL    | **0.04** | 0.15 | 1.49 | 0.15 | **0.24** | 0.60 | 4.51 |
|              | Rust    | 0.05 | **0.12** | **0.67** | **0.11** | 0.50 | **0.47** | **2.69** |
|              | Node    | 0.06 | 0.20 | 1.39 | 0.27 | 1.50 | 1.42 | 7.91 |
| **p99 (ms)** | NURL    | **0.06** | **0.19** | 2.24 | 0.43 | 26.04 | 1.68 | 13.83 |
|              | Rust    | 0.08 | 0.21 | **0.97** | **0.25** | **1.14** | **0.93** | **5.11** |
|              | Node    | 0.11 | 0.30 | 3.79 | 0.75 | 4.52 | 2.51 | 20.94 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 24 194 | 33 611 | 0.72x | 0.04 | 0.03 |
| 10 | 60 443 | 118 719 | 0.51x | 0.15 | 0.07 |
| 50 | 73 224 | 154 073 | 0.48x | 0.60 | 0.30 |

## 2. HTTP/2 over TLS (ALPN h2)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **20 429** | 47 768 | 48 168 | 46 240 | 63 660 | 56 813 | 87 482 |
|              | Rust    | 16 685 | **60 620** | **121 299** | **69 403** | **151 102** | **88 694** | **158 762** |
|              | Node    | 11 692 | 40 718 | 62 751 | 23 955 | 51 917 | 24 393 | 46 007 |
| **p50 (ms)** | NURL    | **0.05** | 0.20 | 2.07 | 0.20 | **0.33** | 0.75 | 5.54 |
|              | Rust    | **0.05** | **0.13** | **0.75** | **0.13** | 0.57 | **0.58** | **3.10** |
|              | Node    | 0.07 | 0.22 | 1.42 | 0.37 | 1.66 | 1.79 | 9.82 |
| **p99 (ms)** | NURL    | **0.08** | 0.33 | 2.90 | 0.54 | 8.14 | 2.11 | 18.31 |
|              | Rust    | 0.09 | **0.24** | **1.10** | **0.30** | **1.26** | **1.06** | **5.60** |
|              | Node    | 0.15 | 0.34 | 5.16 | 0.68 | 4.17 | 3.10 | 24.61 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 20 429 | 28 215 | 0.72x | 0.05 | 0.03 |
| 10 | 46 240 | 80 640 | 0.57x | 0.20 | 0.10 |
| 50 | 56 813 | 102 056 | 0.56x | 0.75 | 0.43 |

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
