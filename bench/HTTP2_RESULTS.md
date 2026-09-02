# NURL HTTP/2-server peer-comparison

Generated `2026-09-02T16:42:10Z` by `bench/run_http2.sh`. **Do not edit by hand** — the next run overwrites it.

The HTTP/2 companion of [`HTTP_RESULTS.md`](HTTP_RESULTS.md) (which stays HTTP/1.1-only). Each implementation accepts a connection, speaks HTTP/2 (RFC 9113 + HPACK, RFC 7541) and answers every request on every stream with the same 14-byte `Hello, World!\n` body (`text/plain`). Section 1 is cleartext HTTP/2 with prior knowledge (§3.4 — the `PRI * HTTP/2.0` preface, what `curl --http2-prior-knowledge`, `h2load` and `oha --http2` send); section 2 negotiates `h2` over ALPN (§3.3) on a self-signed EC (P-256) certificate, which `oha` accepts with `--insecure`.

The NURL server is `bench/http_server.nu` **unchanged from the HTTP/1.1 benchmark**: the `packages/http` HttpApp facade in `http_app_async` mode serves both protocols on every listener — ALPN decides over TLS, the connection preface decides on cleartext. The Rust peer drives hyper's `http2` connection builder on tokio (rustls with ALPN `h2` for TLS); the Node peer is the built-in `node:http2` module (`allowHTTP1: false` for TLS).

**Cells are `C x P`: C connections, each carrying P concurrent streams** (`oha --http2 -c C -p P`), so C x P requests are in flight. `1 x 100` is one connection multiplexing a hundred streams — HTTP/2's own axis, which HTTP/1.1 has no equivalent for; `50 x 1` is fifty connections with one stream each, the closest thing to the HTTP/1.1 `C = 50` cell.

**Read the throughput columns, not the latency columns, at high in-flight counts.** These are *closed-loop* measurements: `oha` fires the next request on a stream the instant the previous one returns. If a server's in-flight work saturates below C x P, the extra requests queue inside `oha` and never reach the server, so `req/s` is the server's true saturation throughput but the latency percentiles describe only the requests in flight. Such cells are marked ‡ and left un-bold. The effective in-flight count is `req/s x mean-latency` (Little's law).

## Environment

| Item | Value |
|---|---|
| Host | `developer workstation (Linux x86_64)` |
| Kernel | `Linux 7.0.0-30-generic x86_64` |
| CPU | Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz (12 logical cores) |
| Memory | 32770944 KiB |
| Commit | `3f0a17fb1f598db04521e2b19d3b15defc220c98` |
| NURL | `v0.58.0-15-g3f0a17fb-dirty` |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v24.15.0 |
| Load generator | oha 1.8.0 |

| Setting | Value |
|---|---|
| Throughput/latency | median of 3 x 10 s closed-loop runs |
| Cells (C x P) | 1x1 , 1x10 , 1x100 , 10x1 , 10x10 , 50x1 , 50x10 |
| TLS cert | self-signed EC P-256, `CN=localhost`, ALPN `h2` |

## 1. Cleartext HTTP/2 (h2c, prior knowledge)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **23 472** | **82 435** | **113 653** | **100 997** | **245 943** | **154 093** | 340 613 |
|              | Rust    | 8 611 | 21 001 | 27 224 | 93 718 | 154 637 | 134 621 | **382 492** |
|              | Node    | 6 110 | 18 388 | 45 929 | 16 889 | 39 261 | 17 047 | 37 444 |
| **p50 (ms)** | NURL    | **0.04** | **0.12** | **0.86** | **0.09** | **0.24** | **0.29** | **1.14** |
|              | Rust    | 0.10 | 0.32 | 2.39 | 0.10 | 0.28 | 0.33 | 1.25 |
|              | Node    | 0.15 | 0.52 | 1.95 | 0.51 | 2.16 | 2.78 | 12.21 |
| **p99 (ms)** | NURL    | **0.08** | **0.19** | **1.32** | **0.20** | 2.59 | **0.90** | 5.15 |
|              | Rust    | 0.23 | 0.69 | 43.02 | 0.23 | **1.39** | 0.99 | **2.69** |
|              | Node    | 0.31 | 0.94 | 10.20 | 1.24 | 8.70 | 5.65 | 33.45 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 23 472 | 21 247 | 1.10x | 0.04 | 0.04 |
| 10 | 100 997 | 127 092 | 0.79x | 0.09 | 0.07 |
| 50 | 154 093 | 197 258 | 0.78x | 0.29 | 0.22 |

## 2. HTTP/2 over TLS (ALPN h2)

|              | Server  | 1 x 1 | 1 x 10 | 1 x 100 | 10 x 1 | 10 x 10 | 50 x 1 | 50 x 10 |
|--------------|---------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| **req/s**    | NURL    | **18 842** | **67 783** | **89 944** | **86 235** | **206 158** | **129 105** | 284 854 |
|              | Rust    | 7 127 | 19 337 | 28 612 | 81 267 | 149 632 | 116 699 | **328 745** |
|              | Node    | 5 271 | 16 225 | 46 082 | 14 358 | 37 125 | 14 308 | 32 931 |
| **p50 (ms)** | NURL    | **0.05** | **0.15** | **1.09** | **0.11** | **0.27** | **0.35** | **1.35** |
|              | Rust    | 0.12 | 0.35 | 2.39 | **0.11** | 0.32 | 0.39 | 1.43 |
|              | Node    | 0.17 | 0.62 | 1.94 | 0.63 | 2.34 | 3.38 | 13.90 |
| **p99 (ms)** | NURL    | **0.10** | **0.22** | **1.64** | **0.23** | 3.43 | 1.08 | 6.03 |
|              | Rust    | 0.28 | 0.72 | 43.02 | 0.26 | **1.25** | **1.04** | **3.19** |
|              | Node    | 0.36 | 1.07 | 8.92 | 1.41 | 10.07 | 6.10 | 36.27 |

### NURL, same server and listener: HTTP/2 (P = 1) vs HTTP/1.1

The same binary, the same port, `oha` with and without `--http2`. The gap is the protocol's own cost — framing, HPACK, flow-control bookkeeping — with everything else held equal.

| C | HTTP/2 req/s | HTTP/1.1 req/s | HTTP/2 / HTTP/1.1 | HTTP/2 p50 (ms) | HTTP/1.1 p50 (ms) |
|--:|------------:|--------------:|------------------:|----------------:|-----------------:|
| 1 | 18 842 | 17 336 | 1.09x | 0.05 | 0.05 |
| 10 | 86 235 | 103 454 | 0.83x | 0.11 | 0.09 |
| 50 | 129 105 | 156 288 | 0.83x | 0.35 | 0.28 |

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
