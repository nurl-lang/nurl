# NURL HTTP-server peer-comparison

> Hardware: Intel Core i7-5930K @ 3.50 GHz (6 physical / 12 logical
> cores), Ubuntu 24.04 (kernel 6.17), Linux x86_64, all loopback.
> Compilers: Rust 1.82.0 (hyper 1.9.0, tokio 1.52, `lto=fat`), Node
> v24.15.0 (built-in `http`). Load generator: oha 1.8.0 (HTTP/1.1,
> keep-alive enabled).
>
> Numbers are **median of 3 × 10 s runs per cell**. Reproduce with
> `bench/run_http.sh --concurrencies "1 10 50 200" --duration 10`
> (ITERS=3 by default).

## Headline numbers

The path under test is a `GET /` returning `Hello, World!\n` (14 bytes,
`text/plain; charset=utf-8`). No router middleware, no JSON, no
metrics. All three implementations accept a TCP connection, parse one
HTTP/1.1 request, write the 14-byte body, keep-alive.

|              | Server  | C = 1   | C = 10   | C = 50   | C = 200  |
|--------------|---------|--------:|---------:|---------:|---------:|
| **req/s**    | NURL    | 14 451  | **68 960** |  60 897  |  59 044  |
|              | Rust    | 14 507  |  47 703  | **86 699** | **114 694** |
|              | Node    |  8 708  |  16 726  |  17 108  |  15 555  |
| **p50 (ms)** | NURL    | **0.06**| **0.08** | **0.10** | **0.11** |
|              | Rust    |   0.07  |   0.15   |   0.41   |   1.33   |
|              | Node    |   0.11  |   0.54   |   2.90   |  12.89   |
| **p99 (ms)** | NURL    | **0.14**|   0.56   |   0.67   |   0.62   |
|              | Rust    |   0.11  |   1.16   |   2.82   |   6.19   |
|              | Node    |   0.22  |   1.98   |   6.13   |  20.95   |

(Best per row in **bold**. Higher is better for req/s; lower for
latency.)

## Reading the table

### Single client (C = 1)

The three implementations are dominated by per-request CPU work. NURL
and Rust hyper land within < 1 % of each other (14 451 vs 14 507).
Node trails ~1.7×.

### Light parallel (C = 10)

NURL's `server_run_pool` runs 10 worker threads (see
`bench/http_server.nu`); 10 in-flight connections fit inside that
pool. Rust's tokio multi-thread runtime defaults to one worker per
logical core (12 here); at C = 10 the runtime is over-provisioned.
NURL: 69 k/s, p99 0.56 ms. Rust: 48 k/s, p99 1.16 ms.

### Moderate parallel (C = 50)

NURL's 10-worker pool is saturated (~62 k/s). Rust's multi-thread
scheduler reaches 87 k/s. NURL p50 stays at 0.10 ms; Rust p50 0.41 ms.

### High parallel (C = 200)

Rust hyper reaches 115 k/s by saturating every core. NURL holds 59 k/s
— its 10-worker pool is the throughput ceiling. NURL p50 0.11 ms, p99
0.62 ms. Rust p99 6.19 ms.

Node plateaus at ~16 k/s with rising latency.

## Configuration notes

- NURL runs 10 worker threads; Rust hyper runs one tokio worker per
  logical core (12 here). Each implementation uses its conventional
  default configuration.
- Loopback HTTP/1.1 only. No HTTPS measured. No HTTP/2 measured.
- Go is not included. `bench/run_http.sh` reserves a lane for
  `bench/http_server.go`.
- The hardware is 11 years old; absolute numbers will differ on a
  modern CPU.
