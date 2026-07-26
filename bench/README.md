# NURL benchmarks

Fifteen benchmarks. Five languages each — **NURL**, **C**, **Rust**,
**Node** and **Python** — one algorithm per benchmark, one runner, one
report. A row is timed only when all five implementations print the same
line, so no cell can be fast by computing something else.

```sh
./build.sh                 # build/nurlc + stdlib/runtime.o must exist first
./bench/bench.sh           # the whole suite (~10 min; Python is the long pole)
./bench/bench.sh --quick   # one run per cell, for a smoke test
./bench/bench.sh --bench lcg --bench sieve
./bench/bench.sh --stdout  # print the report, write nothing
```

It writes two files:

| File | For | Contents |
|---|---|---|
| [`results/latest.json`](results/latest.json) | machines | Run times, compile times, checksums, host and toolchain versions. The landing page's benchmark table is generated from this file at publish time by `tools/gen-bench-table.mjs`. |
| [`RESULTS.md`](RESULTS.md) | humans | The same run rendered: run times, compile times, the correctness gate, and the process-start-up floor. |

Both are refreshed by [`.github/workflows/bench.yml`](../.github/workflows/bench.yml)
on a fixed `ubuntu-latest` runner — weekly, and on demand from the Actions
tab. Those runs commit the refreshed files, which is how nurl-lang.org's
numbers stay honest without anyone typing a figure into HTML.

## The contract

Every implementation of a benchmark:

1. takes no arguments and reads no input except `data.json` where the
   benchmark says so;
2. computes a checksum and **prints exactly one line** — that value in
   decimal, masked to 63 bits so the languages without an unsigned
   64-bit type can print it too;
3. prints nothing else.

`bench.sh` runs all five, compares the five lines, and only then times
them. A mismatch fails the run rather than producing a table with a
plausible-looking wrong cell in it.

The `// benchmark-contract:` line at the top of each source file is the
algorithm's parameters in one line — seed, iteration count, constants —
so the five files can be checked against each other by reading, not just
by running.

## The roster

Defined in [`manifest.tsv`](manifest.tsv), which is what both `bench.sh`
and `perfstat.sh` read.

| Benchmark | Shape |
|---|---|
| `lcg` | Loop-carried integer dependency, 64-bit wrap-around |
| `affine_mix` | Shift/add/mask chain over a 58-bit state, no multiply |
| `packet_classifier` | A data-dependent 50/50 branch the predictor cannot learn |
| `ring_write` | Dependent store per iteration plus address computation |
| `histogram_bins` | Read-modify-write at a data-dependent index |
| `prefix_scan` | Store-bound fill, then a serial load/add dependency chain |
| `binary_search` | Pointer-chasing: each load address depends on the last compare |
| `sort_window` | Compare/branch/store mill over a 64-byte window |
| `bloom_filter` | Four unpredictable loads per query over a 2 KB working set |
| `hash_join` | Cheap Bloom early-out plus a rare, branchy join path |
| `sieve` | Irregular-stride byte writes, then one linear scan |
| `fib` | The function-call path: ~29.8M calls, no memoisation |
| `collatz` | Control-flow-heavy inner loop with no array at all |
| `matmul` | Triple-nested loop, flat indexing, column-strided reads |
| `json_parse` | Allocator pressure, string handling, recursive descent |

No two rows measure the same shape. That is a deliberate property, and
the reason the previous `stream_lcg` kernel is gone: it was `lcg` with
32-bit constants, so it made the table longer without making it say more.

### How the languages are held to the same algorithm

Ten of the fifteen are defined over 64-bit unsigned integers, which two
of the five languages do not have:

* **Python** has arbitrary-precision integers, so every step masks
  explicitly. Always exact, and slow — that is the measurement.
* **JavaScript** has no 64-bit integer at all. Where the algorithm
  genuinely needs 64 bits (`lcg`, `affine_mix`, `bloom_filter`,
  `hash_join`) the port uses `BigInt`; where 32 bits suffice it uses
  Numbers with `Math.imul`, which is exactly defined as the wrapping
  32-bit multiply. Each file states which and why in its header.

The rule is *each language at its fastest exact representation*, and the
checksum gate is what keeps "fastest" from drifting into "different".

## What is **not** in the timing suite

* `brackets`, `csv_sum`, `histogram`, `quicksort`, `rot13` and `words`
  are the held-out corpus for the generation-accuracy study in
  [`genacc/`](genacc/) and the token study in
  [`TOKEN_EFFICIENCY.md`](TOKEN_EFFICIENCY.md). Their workloads are a
  single short string: they measure process start-up, not a language.
  [`verify.sh`](verify.sh) is their cross-language correctness gate.

  `genacc/` is self-contained: each task's prompt *and* its expected
  output are pinned in [`genacc/tasks.json`](genacc/tasks.json), and the
  scorer never reads the files here. So a benchmark that appears in both
  places can hold a different workload in each — `matmul` is 256×256 in
  the timing suite (128×128 was too small to measure) and stays 128×128
  in the frozen genacc task, whose recorded model scores would otherwise
  stop describing the task they were measured against.
* `http_server.{nu,js}` + `rust_http_server/` are the HTTP-server peer
  benchmark, driven by [`run_http.sh`](run_http.sh) with `oha` as the
  load generator; results in [`HTTP_RESULTS.md`](HTTP_RESULTS.md). It
  measures requests per second, not wall clock, so it has its own runner.
* `stdlib_hotpath.nu` is a NURL-only profiling probe with no peers.

## Beyond wall clock

[`perfstat.sh`](perfstat.sh) builds the NURL binaries and reports
**retired instructions and core cycles** from the CPU's own counters:

```sh
./bench/perfstat.sh --save ref.tsv     # record a baseline
./bench/perfstat.sh --against ref.tsv  # compare after a compiler change
```

Wall clock has several per cent of run-to-run drift, so anything under
~10 % there is noise. Instructions are essentially deterministic for
these single-threaded kernels and cycles do not move with the frequency
governor, which makes a 1 % regression visible. Use `bench.sh` to compare
languages, `perfstat.sh` to compare two versions of NURL.

## Reading the numbers

* Compare a cell against the **floor row** in `RESULTS.md` (an empty
  program in the same language). A cell near the floor is process
  start-up, not the benchmark.
* All three compiled back ends are LLVM-based and all three are allowed
  to be clever — LLVM will fold an affine recurrence or pick a different
  unroll factor per language. A cell measures optimised throughput of the
  same algorithm, not the source-level iteration count.
* Absolute numbers are machine-specific. Compare deltas between runs on
  the same machine or the same CI runner spec; the committed results
  file always records which host produced it.
