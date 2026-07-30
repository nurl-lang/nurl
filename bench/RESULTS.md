# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T09:19:43Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373460 KiB |
| Commit | `b23c7d5308c947f65c3edeb0f4cd7d6ca7b6ad9a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30529972645 |
| NURL | `v0.29.0-8-gb23c7d5` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.1 |
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
| _(floor: empty program)_ | _1.446_ | _1.509_ | _1.599_ | _18.668_ | _13.737_ |
| `lcg` | 34.628 | **34.613** | 37.918 | 1422.031 | 4206.588 |
| `packet_classifier` | **49.463** | 49.520 | 49.706 | 124.227 | 3530.595 |
| `ring_write` | **37.075** | 37.201 | 37.353 | 57.574 | 5153.809 |
| `histogram_bins` | **34.775** | 34.870 | 34.955 | 58.942 | 4807.723 |
| `prefix_scan` | **19.114** | 19.191 | 19.250 | 56.849 | 3617.744 |
| `binary_search` | **27.733** | 27.846 | 35.842 | 86.747 | 4816.235 |
| `sort_window` | 24.097 | 24.125 | **23.693** | 128.914 | 8498.098 |
| `bloom_filter` | **15.502** | 15.987 | 16.227 | 2161.592 | 6045.691 |
| `hash_join` | **22.742** | 24.019 | 24.251 | 2665.759 | 6428.176 |
| `sieve` | 16.388 | **16.107** | 16.173 | 56.119 | 2867.573 |
| `fib` | **21.904** | 26.134 | 23.089 | 112.184 | 1010.177 |
| `collatz` | **10.903** | 10.970 | 11.083 | 42.650 | 584.062 |
| `matmul` | **35.366** | 36.524 | 36.023 | 66.173 | 2601.945 |
| `json_parse` | **6.673** | 7.211 | 9.720 | 31.238 | 30.477 |
| `nbody` | 36.183 | 36.214 | **34.447** | 75.002 | 2532.021 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc` emits LLVM IR, then `clang`
lowers and links it against `stdlib/runtime.o`. **NURL total** is the
number comparable to the C and Rust columns. The floor row is what each
toolchain costs for a program that does nothing — for NURL that is
dominated by the LTO link every NURL binary pays for, so subtract it to
read the marginal cost of the benchmark itself. Node and Python have no
column here: they compile at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.579_ | _69.675_ | _**72.254**_ | _51.584_ | _52.889_ |
| `lcg` | 2.690 | 73.139 | **75.829** | 57.043 | 59.462 |
| `packet_classifier` | 2.836 | 76.098 | **78.934** | 58.769 | 59.709 |
| `ring_write` | 2.976 | 77.097 | **80.073** | 59.245 | 60.727 |
| `histogram_bins` | 3.155 | 77.913 | **81.068** | 60.772 | 62.839 |
| `prefix_scan` | 3.160 | 79.241 | **82.401** | 62.055 | 62.014 |
| `binary_search` | 3.359 | 77.994 | **81.353** | 59.761 | 64.636 |
| `sort_window` | 3.440 | 83.616 | **87.056** | 64.813 | 67.277 |
| `bloom_filter` | 3.648 | 81.234 | **84.882** | 64.716 | 64.904 |
| `hash_join` | 7.099 | 165.694 | **172.793** | 96.970 | 92.636 |
| `sieve` | 3.175 | 82.430 | **85.605** | 68.627 | 70.633 |
| `fib` | 2.747 | 76.328 | **79.075** | 59.980 | 59.469 |
| `collatz` | 3.082 | 80.847 | **83.929** | 61.862 | 63.447 |
| `matmul` | 3.714 | 85.343 | **89.057** | 69.957 | 79.800 |
| `json_parse` | 62.172 | 557.256 | **619.428** | 100.282 | 152.580 |
| `nbody` | 5.569 | 94.661 | **100.230** | 82.055 | 81.066 |

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
