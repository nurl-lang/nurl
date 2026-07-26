# NURL benchmarks

Two independent benchmark sets live here:

1. **The four-language set** — NURL against **Python 3** (interpreter),
   **Rust** (LLVM-backed compiled systems language) and **Node.js**
   (V8 JIT). Driven by [`run.sh`](run.sh); results in
   [`RESULTS.md`](RESULTS.md).
2. **The u64 kernel set** — NURL against **C** and **Rust** only, ten
   deterministic integer kernels with a byte-exact cross-language
   checksum gate, measuring **both compile time and run time**. Driven by
   [`run_micro.sh`](run_micro.sh); see
   [the u64 kernel set](#the-u64-kernel-set) below.

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
├── words.{nu,py,rs,js}          — count words (runs of letters) in a string
├── brackets.{nu,py,rs,js}       — max nesting depth of a bracket string
├── csv_sum.{nu,py,rs,js}        — sum the integers in a ','/';' grid
├── histogram.{nu,py,rs,js}      — highest single-digit count in a string
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

The u64 kernel set sits alongside it, one file per language per kernel:

```
bench/
├── affine_mix.{nu,c,rs}         — 50M chained affine steps over a 58-bit state
├── stream_lcg.{nu,c,rs}         — 50M steps of a 32-bit LCG (the tightest loop)
├── ring_write.{nu,c,rs}         — 50M LCG steps, each storing into a 64-slot ring
├── packet_classifier.{nu,c,rs}  — 50M iterations picking one of two LCGs (50/50 branch)
├── histogram_bins.{nu,c,rs}     — 20M increments of 64 bins at a data-dependent index
├── prefix_scan.{nu,c,rs}        — 1M batches of "fill 16 slots, then running-sum them"
├── binary_search.{nu,c,rs}      — 5M lower-bound searches over a 64-entry table
├── sort_window.{nu,c,rs}        — 5M bubble-sorts of an 8-element window
├── bloom_filter.{nu,c,rs}       — 256-word split-block Bloom filter, 1M queries
├── hash_join.{nu,c,rs}          — 256-slot group-probed hash table behind a Bloom filter
├── run_micro.sh                 — compile-time + run-time runner, writes the report below
└── bench_results_YYYYMMDDHHMM.md — captured compile + run numbers
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
| `words` | Char-level state machine | Counts maximal letter-runs; branchy scan with no array. |
| `brackets` | Stack + matching | Balanced-bracket check with a manual stack; max nesting depth. |
| `csv_sum` | Parsing + manual atoi | Splits a separated grid and accumulates integers from digits. |
| `histogram` | Array-indexed tally | Per-digit counts then a max; the string-plus-small-array shape. |

The four string tasks (`words`/`brackets`/`csv_sum`/`histogram`) were added as a
**held-out set** for the generation-accuracy study (`genacc/`) — see its
`RESULTS.md` for why that matters.

The five algorithmic benches use a float64-safe LCG fill (modulus 2²⁰) so
every language stays bit-exact without any i64-wrap special-casing.

## The u64 kernel set

Ten kernels, each with a NURL, C and Rust implementation of the *same*
algorithm on `u64` arithmetic. Unlike the four-language set above, this
one is aimed squarely at the compiled-language comparison, and it
measures compile time as well as run time:

```sh
./bench/run_micro.sh                    # 5 timed compiles + 9 timed runs per cell
./bench/run_micro.sh --bench hash_join  # one kernel
./bench/run_micro.sh --reps 3 --compile-reps 1
```

The runner compiles everything first, writes the compile-time table, runs
the correctness gate, then runs the binaries and appends the run-time
table — all into `bench_results_YYYYMMDDHHMM.md`.

**Protocol.** Every kernel is silent and returns `checksum & 0x7f` as its
exit status, so nothing measures I/O. Built in verify mode it instead
writes the 8 little-endian checksum bytes to stdout:

| Language | Verify build | Verify invocation |
|---|---|---|
| NURL | (same binary) | `./x --verify` |
| C | `clang -O2 -DBENCH_VERIFY x.c` | `./x` |
| Rust | `rustc -O --cfg bench_verify x.rs` | `./x` |

The three dumps must be byte-identical; the report says so per kernel.
All ten currently agree, which is what makes the timings comparable — a
speed number for a program computing something else is worthless.

**Reading the numbers.** Two caveats the report repeats:

* NURL's compile time is two stages, `nurlc` (IR) then `clang` (codegen +
  link). The `nurlc` stage is single-digit milliseconds; nearly all of the
  rest is the `-flto` link against `stdlib/runtime.o`, a fixed cost every
  NURL binary pays. The report's floor row (an empty program) makes that
  visible so the marginal cost is readable.
* The runner drives those two stages directly rather than going through
  `nurl.sh`. The driver runs the same `nurlc` and the same `clang` line and
  produces a **byte-identical** binary, but it first probes the environment
  (trial links against `-lsqlite3`, `-lzstd`, …) for about **200 ms** per
  invocation — fixed, input-independent, and environment detection rather
  than compilation. Charging that to NURL's column against a bare
  `clang x.c`, which has no analogue, would measure the wrong thing.
* All three back ends are LLVM and all three are allowed to be clever —
  LLVM composes the affine LCG recurrence and folds several iterations
  into one multiply-add. A cell measures optimised throughput, not the
  source-level iteration count, and differing unroll factors between the
  languages are part of what is being measured.

**Toolchain requirement.** `bloom_filter`, `hash_join`, `ring_write` and
`histogram_bins` store at an index whose type is `u64`, which needs a
`nurlc` that lowers the index operand of a store `getelementptr` — fixed
in this tree, broken in 0.25.0 and earlier, where `nurlc` emits
`getelementptr i64, i64* %p, u64 %idx` and the C compiler rejects the
module with `error: expected type`. Build the set with the tree's
`build/nurlc`, which is what `run_micro.sh` does. A second reason not to
reach for an older installed toolchain: 0.25.0's driver prefers its
bundled `zig cc`, which silently drops `-O` for `.ll` inputs, so its
binaries come out `-O0` — measured here at 20× slower on `stream_lcg`
and 4.4× on `sort_window`.

`bench/allocator_stress.rs` was considered for this set and dropped: it
was not self-contained (it `#[path]`-included a file from another
project), and a multi-threaded allocator stress test cannot have the
deterministic byte-exact checksum gate the rest of the set relies on, so
there was nothing honest to compare.

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
