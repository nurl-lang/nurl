# NURL benchmark results

> Hardware: Intel Core i7-5930K @ 3.50 GHz (12 logical cores), Ubuntu
> 24.04 (kernel 6.17), Linux x86_64. Compilers: Rust 1.82.0,
> Python 3.12.3, Node v24.15.0.
>
> Numbers are **median wall-clock ms across 5 runs** per cell, with a
> 60 s per-run timeout. Reproduce with `./bench/run.sh --timeout 60 5`.

## Headline table

| Benchmark         | NURL  | Python  | Rust  | Node    |
|-------------------|------:|--------:|------:|--------:|
| `lcg`             |  10   | 27 459  |  16   |  9 680  |
| `sieve`           |  69   |  5 898  |  62   |    142  |
| `json_parse`      |  14   |     34  |   5   |     47  |

(Lower is better. All times ms.)

## Reading the table

### lcg

100 million iterations of the MMIX linear congruential generator (a
single i64 multiply + add per step, with i64 wrap-around). NURL and
Rust are within measurement noise of each other; both compile through
LLVM `-O2` to the same `imul`/`add` kernel. Python's pure-int loop
is ~28 seconds. Node BigInt does not JIT into native multiplications.

### sieve

Sieve of Eratosthenes to π(10 000 000) = 664 579. NURL and Rust again
land within noise: both compile to the same array-mark + scan loops.
Node's typed-array path (`Uint8Array`) lands ~2× behind. Python's
`bytearray` loop is ~6 seconds.

### json_parse

5 parses of a deterministic ~64 KB JSON file (500 records, generated
by `bench/gen_data.py` with `random.seed(42)`). Each language uses
what ships in its standard distribution: Python's stdlib `json` (a C
extension), Node's built-in `JSON.parse` (V8 C++), NURL's pure-NURL
`stdlib/ext/json.nu`. Rust has no JSON in stdlib, so the Rust file
includes a small hand-written recursive-descent parser.

NURL's pure-NURL parser runs the 64 KB payload at ~22 MB/s sustained
(C-extension Python: ~10 MB/s; zero-copy hand-written Rust:
~60 MB/s). The Rust parser stores `&str` slices into the input rather
than allocating fresh strings.

## Scope

- No warm-up loop, no variance reporting beyond a median, no
  perf-counter capture. Cells are good for order-of-magnitude
  reasoning.
- No HTTP-server-vs-Go benchmark. See [`HTTP_RESULTS.md`](HTTP_RESULTS.md)
  for the HTTP-server peer comparison (NURL / Rust hyper / Node http).

## Reproducing

```sh
./build.sh                       # builds build/nurlc + stdlib/runtime.o + runs tests
./bench/run.sh --timeout 60 5
```

The runner detects which tools are installed. Missing tools print
`n/a`; a timed-out cell renders as `>60s`.
