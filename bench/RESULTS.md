# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-20T08:45:43Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `ee058bacd2ec9f43890e1d0470d80c196dbc4d84` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32350008150 |
| NURL | `v0.45.0-21-gee058bac` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.2 |
| Python | Python 3.12.3 |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `clang -O2`, Rust `-C opt-level=2` |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.775_ | _1.826_ | _2.001_ | _25.690_ | _19.713_ |
| `lcg` | **39.602** | 39.819 | 39.847 | 2067.609 | 5141.990 |
| `packet_classifier` | **56.880** | 56.883 | 57.028 | 164.113 | 4530.393 |
| `ring_write` | **42.766** | 42.780 | 42.942 | 67.602 | 6205.104 |
| `histogram_bins` | **40.056** | 41.856 | 40.201 | 69.879 | 6509.073 |
| `prefix_scan` | **22.300** | 22.398 | 22.489 | 67.384 | 4424.398 |
| `binary_search` | **36.901** | 39.243 | 43.745 | 108.517 | 7602.373 |
| `sort_window` | **27.179** | 27.942 | 27.392 | 200.153 | 13701.603 |
| `bloom_filter` | **18.354** | 18.703 | 18.996 | 2849.580 | 7543.581 |
| `hash_join` | **27.410** | 30.488 | 30.416 | 3423.689 | 8302.865 |
| `sieve` | 20.024 | 19.284 | **19.059** | 68.631 | 3292.529 |
| `fib` | **25.741** | 30.545 | 28.788 | 133.457 | 1364.201 |
| `collatz` | **12.827** | 12.878 | 13.083 | 50.904 | 716.775 |
| `matmul` | 34.246 | **34.225** | 34.561 | 80.196 | 3153.967 |
| `json_parse` | 9.555 | **9.228** | 12.334 | 38.072 | 40.849 |
| `nbody` | **25.794** | 41.223 | 39.521 | 102.346 | 3036.024 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc` emits LLVM IR, then `clang`
lowers and links it against `stdlib/runtime.o`. **NURL total** is the
number comparable to the C and Rust columns: a cold compile, measured
against a wiped cache exactly as C and Rust pay their full cost every
time. **NURL rebuild** is the same compile again with the ThinLTO
cache warm — `nurl.sh`'s default on Linux (docs/BUILDING.md → The
ThinLTO cache) — which is what every build after the first costs; C
and Rust have no default equivalent (`ccache`/`sccache` are opt-in
add-ons). The floor row is what each toolchain costs for a program
that does nothing — for NURL that is dominated by the LTO link every
NURL binary pays for, so subtract it to read the marginal cost of the
benchmark itself. Node and Python have no column here: they compile
at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | NURL rebuild | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.116_ | _100.998_ | _**104.114**_ | _65.224_ | _64.160_ | _67.450_ |
| `lcg` | 3.236 | 103.617 | **106.853** | 63.902 | 72.669 | 74.831 |
| `packet_classifier` | 3.387 | 104.046 | **107.433** | 64.435 | 73.886 | 73.525 |
| `ring_write` | 3.500 | 104.010 | **107.510** | 63.868 | 75.004 | 75.687 |
| `histogram_bins` | 3.596 | 123.226 | **126.822** | 64.438 | 76.767 | 80.717 |
| `prefix_scan` | 3.533 | 108.147 | **111.680** | 64.374 | 79.332 | 79.428 |
| `binary_search` | 3.676 | 110.729 | **114.405** | 63.744 | 75.624 | 80.848 |
| `sort_window` | 3.859 | 114.742 | **118.601** | 65.536 | 82.604 | 86.228 |
| `bloom_filter` | 4.021 | 111.540 | **115.561** | 64.564 | 83.649 | 87.108 |
| `hash_join` | 6.830 | 271.610 | **278.440** | 68.139 | 130.633 | 119.746 |
| `sieve` | 3.631 | 105.842 | **109.473** | 63.924 | 86.723 | 88.283 |
| `fib` | 3.258 | 104.203 | **107.461** | 64.803 | 73.814 | 75.796 |
| `collatz` | 3.599 | 111.510 | **115.109** | 66.787 | 73.704 | 75.508 |
| `matmul` | 3.980 | 111.332 | **115.312** | 65.790 | 88.865 | 102.997 |
| `json_parse` | 55.238 | 458.118 | **513.356** | 117.362 | 134.437 | 198.741 |
| `nbody` | 5.361 | 135.351 | **140.712** | 66.921 | 103.785 | 103.155 |

## 3. Correctness gate

Each row is timed only when all five implementations print the same
line. A speed number for a program computing something else is worthless,
so a mismatch drops the row out of the tables above rather than being
reported as a fast cell.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical across 5 languages |
| `packet_classifier` | `4205972061` | identical across 5 languages |
| `ring_write` | `8299504528805184357` | identical across 5 languages |
| `histogram_bins` | `1215643728` | identical across 5 languages |
| `prefix_scan` | `492982549` | identical across 5 languages |
| `binary_search` | `805907445` | identical across 5 languages |
| `sort_window` | `2815490238` | identical across 5 languages |
| `bloom_filter` | `2351703` | identical across 5 languages |
| `hash_join` | `6152419568754618368` | identical across 5 languages |
| `sieve` | `664579` | identical across 5 languages |
| `fib` | `9227465` | identical across 5 languages |
| `collatz` | `350` | identical across 5 languages |
| `matmul` | `393199` | identical across 5 languages |
| `json_parse` | `20` | identical across 5 languages |
| `nbody` | `4595260366167553674` | identical across 5 languages |

## 4. Reading the numbers

* A cell near the floor row is mostly process start-up, dynamic linking
  and page faults rather than the benchmark. The rows worth comparing are
  the ones in the tens of milliseconds and up.
* All three compiled back ends are LLVM-based and all three are allowed to
  be clever: LLVM will fold an affine recurrence or unroll a loop by a
  different factor in each language. A cell measures optimised throughput
  of the same algorithm, not the source-level iteration count.
* Nine of the fifteen benchmarks are defined over 64-bit unsigned integers.
  Python has arbitrary-precision integers and masks; JS has no 64-bit
  integer at all, so those rows use `BigInt` where the algorithm genuinely
  needs 64 bits and Numbers with `Math.imul` where 32 bits suffice. Each
  file says which and why. That gap *is* part of what this table reports.
* `nbody` is the counterweight to the row above, and the only row defined
  over IEEE-754 doubles rather than integers. That is the type JavaScript
  does have — its one numeric type is the double — so Node runs the same
  arithmetic as the compiled backends with no representation tax, and lands
  near 2x C instead of the 30-50x the BigInt rows cost it. It is also the
  only row whose critical path runs through the FPU's long-latency sqrt and
  divide units rather than the integer ALU. All five ports use the same
  operation order and the same struct-of-arrays layout, so the checksum —
  the final energy's bit pattern — is exact across all five.
* `json_parse` is the one row whose gate is "every parser accepted the
  document" rather than a structural checksum: each language uses the
  parser in its own box (Python `json`, Node `JSON.parse`, NURL
  `stdlib/ext/json.nu`), and C and Rust — whose boxes are empty — carry a
  small hand-written recursive-descent parser in the benchmark file.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
