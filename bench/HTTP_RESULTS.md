# NURL HTTP-server peer-comparison

> Hardware: Intel Core i7-5930K @ 3.50 GHz (6 physical / 12 logical
> cores), Ubuntu 24.04 (kernel 7.0), Linux x86_64, all loopback.
> Compilers: Rust 1.82.0 (hyper 1.9.0, tokio 1.52, `lto=fat`), Node
> v24.15.0 (built-in `http`). Load generator: oha 1.8.0 (HTTP/1.1,
> keep-alive enabled). Measured 2026-08-11.
>
> Numbers are **median of 3 × 10 s runs per cell**. Reproduce with
> `bench/run_http.sh --concurrencies "1 10 50 200" --duration 10`
> (ITERS=3 by default).

## Headline numbers

The path under test is a `GET /` returning `Hello, World!\n` (14 bytes,
`text/plain; charset=utf-8`). No JSON, no metrics. All three
implementations accept a TCP connection, parse one HTTP/1.1 request,
write the 14-byte body, keep-alive. The NURL server is built on the
`packages/http` HttpApp facade — the surface a real NURL service
deploys — with a 10-thread worker pool (see `bench/http_server.nu`);
routing goes through the stdlib router, exactly as in production use.

|              | Server  | C = 1   | C = 10   | C = 50   | C = 200  |
|--------------|---------|--------:|---------:|---------:|---------:|
| **req/s**    | NURL    | **15 270** | **166 096** | 144 465  | 150 606  |
|              | Rust    | 13 411  | 148 354  | **210 024** | **294 381** |
|              | Node    | 10 013  |  25 026  |  25 839  |  25 949  |
| **p50 (ms)** | NURL    | **0.06**| **0.06** | **0.06** | **0.06** |
|              | Rust    |   0.07  |   0.06   |   0.20   |   0.63   |
|              | Node    |   0.09  |   0.33   |   1.80   |   7.45   |
| **p99 (ms)** | NURL    | **0.13**| **0.09** | **0.12** | **0.13** |
|              | Rust    |   0.14  |   0.13   |   0.73   |   1.62   |
|              | Node    |   0.18  |   0.77   |   3.85   |  14.73   |

(Best per row in **bold**. Higher is better for req/s; lower for
latency.)

## Reading the table

### Single client (C = 1)

Dominated by per-request round-trip cost. NURL leads Rust hyper 15.3 k
vs 13.4 k (~14 %); Node trails ~1.5×.

### Light parallel (C = 10)

NURL's 10 worker threads match the 10 in-flight connections one-to-one:
166 k/s at p99 0.09 ms — ahead of Rust's 148 k (tokio runs one worker
per logical core, 12 here, so it is over-provisioned at this depth) and
6.6× Node.

### Moderate and high parallel (C = 50 / 200)

NURL's 10 blocking workers are the ceiling: each worker serves one
connection at a time and idles while the response's ACK/next request
round-trips the loopback (~14.6 k req/s per worker; total CPU use is
~3.3 of 12 cores at C = 200). Throughput therefore plateaus at
~145–151 k/s while p50/p99 stay flat at 0.06/0.13 ms for the
connections being served. Rust multiplexes all 200 connections over 12
epoll-driven workers and reaches 294 k/s, trading latency for it (p99
1.62 ms).

Measured scaling of the same NURL binary with a bigger pool
(single 6 s runs, C = 200): 24 workers → 191 k, 64 → 221 k,
200 (thread-per-connection) → 245 k/s at p99 1.78 ms. The fiber-based
`server_run_async` (12 workers + reactor) reaches 250 k/s at p99
3.1 ms; its per-request CPU cost (~2× the blocking path's — scheduler
overhead, see critic.md 2026-08-11) is the current gap to hyper.

Node plateaus at ~26 k/s with rising latency.

## Configuration notes

- NURL runs 10 worker threads; Rust hyper runs one tokio worker per
  logical core (12 here). Each implementation uses its conventional
  default configuration.
- Loopback HTTP/1.1 only. No HTTPS measured. No HTTP/2 measured.
- Go is not included. `bench/run_http.sh` reserves a lane for
  `bench/http_server.go`.
- The hardware is 11 years old; absolute numbers will differ on a
  modern CPU.

## History

- **2026-08-11** — table refreshed (the previous one was months stale:
  NURL 14.5 k / 69.0 k / 60.9 k / 59.0 k across C = 1/10/50/200 —
  the 2.2–2.6× improvement since accumulated across the intervening
  stdlib/runtime performance work, not one change). The server now
  runs on the packages/http facade. Same-day root fixes, A/B-measured
  against that morning's HEAD: stdlib keep-alive loop no longer builds
  a fallback 500 response per request (hoisted to per-connection),
  Connection-header checks stopped allocating, carry-buffer compaction
  became one memmove, header serialisation lost its O(n²)
  `nurl_str_get` walk, the packages/http facade dropped a duplicate
  recover layer (−4 % CPU/request on the pool path, 21.8 → 20.9 µs),
  and the async net path stopped issuing 4 fcntl syscalls per request
  (async hello 237 k → 250 k rps at C = 200, CPU 44.4 → 41.7 µs/req).
