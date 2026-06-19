# NURL benchmarks

Comparative micro-benchmarks between NURL and three peer languages:
**Python 3** (interpreter), **Rust** (LLVM-backed compiled
systems language), and **Node.js** (V8 JIT).

## Layout

Each benchmark ships as one source file per language at the top of
this directory:

```
bench/
├── lcg.{nu,py,rs,js}            — 100M-step linear congruential generator
├── sieve.{nu,py,rs,js}          — Sieve of Eratosthenes, π(10_000_000)
├── json_parse.{nu,py,rs,js}     — parse a ~64 KB JSON file 5 times
├── fib.{nu,py,rs,js}            — recursive Fibonacci(35)
├── collatz.{nu,py,rs,js}        — longest Collatz chain for starts < 100_000
├── matmul.{nu,py,rs,js}         — 128×128 integer matrix product, print the trace
├── quicksort.{nu,py,rs,js}      — in-place quicksort of 5000 ints + checksum
├── rot13.{nu,py,rs,js}          — ROT13 a string, sum the byte values
├── data.json                    — input for json_parse (regenerated on first run)
├── gen_data.py                  — JSON generator (stable seed → deterministic bytes)
├── run.sh                       — compute-benches runner (median wall-clock ms)
├── verify.sh                    — correctness gate: assert all langs print the same bytes
├── RESULTS.md                   — compute-benches captured numbers
├── token_efficiency.py          — BPE-tokeniser-aware token-count study (needs tiktoken)
├── TOKEN_EFFICIENCY.md          — token-count results + honest interpretation
├── http_server.{nu,js}          — hello-world HTTP server peers
├── rust_http_server/            — Rust hyper sibling (Cargo manifest + main.rs)
├── run_http.sh                  — HTTP-peer runner (uses oha for load gen)
└── HTTP_RESULTS.md              — HTTP-peer captured numbers
```

## Running

```sh
./bench/run.sh             # default: 5 runs of every benchmark, 30s/run timeout
./bench/run.sh 3           # 3 runs
./bench/run.sh --bench lcg # just one benchmark
./bench/run.sh --timeout 60 # raise the per-run timeout

./bench/run_http.sh                                        # HTTP peer-bench, defaults
./bench/run_http.sh --concurrencies "1 50 200" --duration 10
DURATION=20 ITERS=5 ./bench/run_http.sh                    # tune via env
```

The compute runner detects which compilers/interpreters are installed
(`build/nurlc`, `python3`, `rustc`, `node`) and prints `n/a` for any
language that is missing. Each cell reports the **median wall-clock ms**
across the requested runs.

The HTTP runner needs `oha` (`cargo install oha --version 1.8.0 --locked`)
as the load generator. It compiles each available server, starts it on
its dedicated loopback port, runs oha for `DURATION` seconds at each
concurrency level (`ITERS` repeats, median wins), then kills the
server. Output is a single Markdown table.

## Benchmark choice rationale

| Bench | Tests | Why this shape |
|---|---|---|
| `lcg` | Tight integer loop, i64 wrap-around, single-stream data dependency | Pure compute; the data dependency between iterations prevents LLVM from collapsing the loop into a closed form. |
| `sieve` | Random-access byte writes + a final scan over the array | Memory bandwidth + branch prediction; the marking step has irregular stride. |
| `json_parse` | Allocator pressure + string handling + recursive descent | Each language uses what ships in its standard distribution (Python `json`, Node `JSON.parse`, NURL `stdlib/ext/json.nu`). Rust has no JSON in stdlib, so the Rust file includes a small hand-written recursive-descent parser. |
| `fib` | Double recursion, no memoisation | Stresses the function-call path and recursion; ~29M calls. |
| `collatz` | Hot while loop + branch + integer arithmetic | A control-flow-heavy inner loop with no array. |
| `matmul` | Triple-nested loop + flat-array indexing | Classic dense-compute kernel; index arithmetic dominates. |
| `quicksort` | Recursion + in-place array mutation | Partition + swap; the checksum only verifies if the sort is correct. |
| `rot13` | Character-level string scan + arithmetic | The string-processing shape, where NURL's glyph surface is most out-of-distribution for BPE tokenisers. |

The five algorithmic benches use a float64-safe LCG fill (modulus 2²⁰) so
every language stays bit-exact without any i64-wrap special-casing.

## Verifying correctness

A token or speed comparison only means something if every language computes
the **same answer**. `bench/verify.sh` compiles and runs each benchmark in
every available language and asserts their stdout is byte-identical:

```sh
./bench/verify.sh            # all benches
./bench/verify.sh fib rot13  # a subset
```

## Token efficiency

`bench/token_efficiency.py` counts real BPE tokens (via `tiktoken`:
`cl100k`, `o200k`, `gpt2`) for every benchmark in all four languages and
writes [`TOKEN_EFFICIENCY.md`](TOKEN_EFFICIENCY.md). **The honest headline:
on today's production tokenisers NURL is *not* more token-efficient than
Python — it costs ~1.7× the tokens (median), because it is out-of-distribution
for BPEs trained on Python/Rust/JS.** The file explains why, and why the
defensible LLM-native claim is grammar *regularity* and first-pass compile
success, not raw token count.

```sh
python3 -m venv bench/_venv && bench/_venv/bin/pip install tiktoken
bench/_venv/bin/python bench/token_efficiency.py > bench/TOKEN_EFFICIENCY.md
```

## Generation accuracy

Token count is not the LLM-native claim worth defending; **first-pass compile
success** is. [`genacc/`](genacc/) is a harness that asks a fixed model to
write each task in each language and scores how often the result compiles and
runs correctly with zero edits — the dimension the token study cannot measure.
It ships tasks, a generator, a scorer, and a reference oracle, but no model
results (running it needs an `ANTHROPIC_API_KEY`). See
[`genacc/README.md`](genacc/README.md).

## Scope

Numbers should reproduce within ~20 % on any modern x86_64 host. There
is no warm-up loop and no statistical analysis beyond a median; cells
are suitable for order-of-magnitude reasoning.

Go is not currently included. `bench/run_http.sh` reserves a lane for
`bench/http_server.go`; adding it produces a four-column table.

See [`RESULTS.md`](RESULTS.md) for the compute-benches numbers and
[`HTTP_RESULTS.md`](HTTP_RESULTS.md) for the HTTP-server peer table.
