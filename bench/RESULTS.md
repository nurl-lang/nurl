# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T23:10:49Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `61ab4ef9d43141045829df48f1030eda2505a15b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31545142654 |
| NURL | `v0.38.0-22-g61ab4ef9` |
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
| _(floor: empty program)_ | _1.712_ | _1.781_ | _1.878_ | _24.106_ | _18.611_ |
| `lcg` | **39.601** | 39.701 | 39.821 | 2054.112 | 5132.555 |
| `packet_classifier` | **56.835** | 56.869 | 56.912 | 163.572 | 4443.878 |
| `ring_write` | **42.650** | 42.725 | 42.890 | 68.424 | 6355.207 |
| `histogram_bins` | **39.943** | 41.621 | 40.188 | 68.222 | 6248.485 |
| `prefix_scan` | **22.084** | 22.139 | 22.293 | 67.223 | 4835.487 |
| `binary_search` | 40.175 | **38.849** | 43.693 | 107.899 | 6087.555 |
| `sort_window` | 27.594 | 27.794 | **27.284** | 198.958 | 11680.051 |
| `bloom_filter` | **18.203** | 18.463 | 18.546 | 2851.577 | 7536.874 |
| `hash_join` | **28.169** | 30.405 | 30.102 | 3421.012 | 8481.473 |
| `sieve` | 20.948 | 20.473 | **20.330** | 68.004 | 3267.909 |
| `fib` | **25.496** | 30.034 | 28.381 | 131.509 | 1379.556 |
| `collatz` | **12.440** | 12.476 | 12.631 | 50.240 | 716.352 |
| `matmul` | 33.860 | **33.819** | 33.852 | 75.907 | 3175.316 |
| `json_parse` | 8.914 | **8.911** | 11.861 | 35.339 | 37.645 |
| `nbody` | 41.041 | 40.961 | **39.111** | 101.322 | 3022.764 |

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
| _(floor: empty program)_ | _2.999_ | _84.932_ | _**87.931**_ | _60.696_ | _62.525_ |
| `lcg` | 3.072 | 92.183 | **95.255** | 71.827 | 70.965 |
| `packet_classifier` | 2.955 | 92.334 | **95.289** | 72.261 | 69.370 |
| `ring_write` | 3.119 | 93.347 | **96.466** | 73.900 | 72.898 |
| `histogram_bins` | 3.233 | 98.743 | **101.976** | 75.581 | 74.041 |
| `prefix_scan` | 3.300 | 99.435 | **102.735** | 77.416 | 75.423 |
| `binary_search` | 3.380 | 98.092 | **101.472** | 74.405 | 77.591 |
| `sort_window` | 3.527 | 105.754 | **109.281** | 81.729 | 83.424 |
| `bloom_filter` | 3.605 | 101.376 | **104.981** | 79.795 | 103.117 |
| `hash_join` | 5.689 | 213.066 | **218.755** | 121.824 | 112.108 |
| `sieve` | 3.153 | 94.296 | **97.449** | 79.465 | 79.114 |
| `fib` | 2.913 | 87.230 | **90.143** | 67.622 | 68.433 |
| `collatz` | 3.124 | 91.679 | **94.803** | 69.256 | 70.248 |
| `matmul` | 3.387 | 98.186 | **101.573** | 81.556 | 93.775 |
| `json_parse` | 44.503 | 540.756 | **585.259** | 124.531 | 179.269 |
| `nbody` | 4.498 | 109.772 | **114.270** | 98.355 | 92.310 |

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
