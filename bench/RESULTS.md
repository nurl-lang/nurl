# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-29T21:22:36Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `a6d4c483f66d8b322b53b90bd19e7e98f4b92e0c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30491847425 |
| NURL | `v0.28.0-6-ga6d4c48` |
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
| _(floor: empty program)_ | _1.434_ | _1.473_ | _1.582_ | _19.093_ | _13.804_ |
| `lcg` | **34.364** | 34.480 | 34.606 | 1419.259 | 4106.033 |
| `packet_classifier` | **49.439** | 49.451 | 49.600 | 122.792 | 3555.095 |
| `ring_write` | **37.152** | 37.170 | 37.299 | 57.312 | 5001.095 |
| `histogram_bins` | **34.749** | 34.875 | 34.916 | 57.749 | 4803.554 |
| `prefix_scan` | **19.141** | 19.189 | 19.289 | 55.105 | 3717.916 |
| `binary_search` | 27.882 | **27.849** | 35.807 | 86.002 | 5671.939 |
| `sort_window` | 23.985 | 24.037 | **23.565** | 127.838 | 10498.010 |
| `bloom_filter` | **15.470** | 15.984 | 16.207 | 2199.765 | 6489.963 |
| `hash_join` | **22.757** | 23.970 | 24.300 | 2666.527 | 6489.872 |
| `sieve` | 16.088 | 15.855 | **15.825** | 55.582 | 2658.571 |
| `fib` | **21.784** | 26.008 | 22.945 | 110.989 | 996.451 |
| `collatz` | **10.827** | 10.839 | 10.917 | 40.201 | 583.204 |
| `matmul` | 35.711 | 35.662 | **35.538** | 64.122 | 2762.101 |
| `json_parse` | **6.488** | 7.083 | 9.598 | 28.706 | 28.902 |
| `nbody` | 35.934 | 35.993 | **34.343** | 74.171 | 2499.087 |

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
| _(floor: empty program)_ | _2.595_ | _70.613_ | _**73.208**_ | _51.355_ | _53.365_ |
| `lcg` | 2.742 | 73.877 | **76.619** | 57.111 | 59.619 |
| `packet_classifier` | 2.832 | 73.877 | **76.709** | 58.677 | 59.555 |
| `ring_write` | 2.975 | 74.135 | **77.110** | 58.918 | 60.993 |
| `histogram_bins` | 3.067 | 76.926 | **79.993** | 60.312 | 63.001 |
| `prefix_scan` | 3.223 | 77.711 | **80.934** | 61.538 | 62.562 |
| `binary_search` | 3.417 | 78.355 | **81.772** | 60.114 | 65.400 |
| `sort_window` | 3.445 | 81.985 | **85.430** | 64.151 | 68.000 |
| `bloom_filter` | 3.615 | 80.714 | **84.329** | 65.025 | 65.345 |
| `hash_join` | 7.477 | 163.780 | **171.257** | 95.973 | 91.897 |
| `sieve` | 3.148 | 77.943 | **81.091** | 65.689 | 68.179 |
| `fib` | 2.704 | 72.520 | **75.224** | 56.929 | 58.056 |
| `collatz` | 2.979 | 75.680 | **78.659** | 58.435 | 60.809 |
| `matmul` | 3.889 | 81.340 | **85.229** | 66.862 | 78.392 |
| `json_parse` | 60.331 | 535.879 | **596.210** | 97.902 | 145.917 |
| `nbody` | 6.096 | 88.476 | **94.572** | 77.984 | 78.874 |

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
