# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T02:30:57Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377692 KiB |
| Commit | `33ea5f250b36da2761671f25e442116beee489e9` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31452363585 |
| NURL | `v0.36.0-87-g33ea5f25` |
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
| _(floor: empty program)_ | _1.786_ | _1.735_ | _1.898_ | _24.734_ | _17.147_ |
| `lcg` | 39.376 | **39.354** | 39.458 | 1878.547 | 5187.929 |
| `packet_classifier` | **56.500** | 56.615 | 56.682 | 162.012 | 4417.200 |
| `ring_write` | 42.534 | **42.487** | 42.715 | 68.316 | 6315.593 |
| `histogram_bins` | **40.020** | 41.701 | 40.134 | 67.774 | 6067.487 |
| `prefix_scan` | 22.191 | **22.183** | 22.274 | 66.582 | 4633.965 |
| `binary_search` | 39.870 | **38.486** | 43.578 | 107.508 | 6009.053 |
| `sort_window` | 27.729 | 27.699 | **26.958** | 198.067 | 11567.935 |
| `bloom_filter` | **18.154** | 18.250 | 18.477 | 2866.504 | 7421.617 |
| `hash_join` | **28.069** | 30.282 | 30.116 | 3415.894 | 8114.795 |
| `sieve` | 21.509 | **18.980** | 20.446 | 67.756 | 3567.952 |
| `fib` | **25.444** | 30.135 | 28.368 | 133.415 | 1344.002 |
| `collatz` | **12.441** | 12.511 | 12.608 | 49.622 | 711.083 |
| `matmul` | 33.727 | **33.699** | 34.227 | 77.885 | 3125.928 |
| `json_parse` | 42.647 | **8.938** | 11.763 | 35.230 | 37.614 |
| `nbody` | 41.166 | 41.182 | **39.177** | 102.421 | 3042.153 |

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
| _(floor: empty program)_ | _2.973_ | _80.653_ | _**83.626**_ | _58.796_ | _63.381_ |
| `lcg` | 2.790 | 89.158 | **91.948** | 68.008 | 69.884 |
| `packet_classifier` | 2.830 | 89.030 | **91.860** | 67.956 | 68.321 |
| `ring_write` | 3.014 | 91.913 | **94.927** | 70.119 | 71.377 |
| `histogram_bins` | 3.028 | 93.077 | **96.105** | 72.735 | 73.796 |
| `prefix_scan` | 3.236 | 100.644 | **103.880** | 77.288 | 84.337 |
| `binary_search` | 3.194 | 97.647 | **100.841** | 72.355 | 75.378 |
| `sort_window` | 3.229 | 101.787 | **105.016** | 77.809 | 78.724 |
| `bloom_filter` | 3.649 | 101.387 | **105.036** | 79.796 | 77.084 |
| `hash_join` | 5.643 | 210.863 | **216.506** | 120.595 | 110.447 |
| `sieve` | 3.061 | 96.602 | **99.663** | 80.547 | 81.868 |
| `fib` | 2.916 | 88.322 | **91.238** | 70.911 | 68.086 |
| `collatz` | 2.915 | 90.722 | **93.637** | 68.401 | 70.032 |
| `matmul` | 3.283 | 98.485 | **101.768** | 81.025 | 91.258 |
| `json_parse` | 42.424 | 544.724 | **587.148** | 127.092 | 182.697 |
| `nbody` | 4.375 | 109.898 | **114.273** | 99.622 | 92.120 |

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
