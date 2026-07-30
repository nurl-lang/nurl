# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T13:10:33Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373456 KiB |
| Commit | `9914d3ef84462f75b7a7cd76c24fa22831022c93` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30545330619 |
| NURL | `v0.29.0-25-g9914d3e` |
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
| _(floor: empty program)_ | _1.652_ | _1.692_ | _1.831_ | _21.733_ | _17.103_ |
| `lcg` | **39.244** | 39.334 | 39.433 | 1879.957 | 5128.298 |
| `packet_classifier` | 56.505 | **56.441** | 56.560 | 161.346 | 4455.878 |
| `ring_write` | 42.448 | 42.469 | **42.423** | 65.871 | 6276.929 |
| `histogram_bins` | **39.651** | 41.278 | 39.768 | 65.363 | 5962.073 |
| `prefix_scan` | **21.895** | 21.963 | 22.147 | 66.169 | 4537.953 |
| `binary_search` | 39.967 | **38.375** | 43.358 | 106.859 | 6328.131 |
| `sort_window` | 27.352 | 27.508 | **26.893** | 197.459 | 11464.821 |
| `bloom_filter` | **18.030** | 18.225 | 18.485 | 2825.858 | 7967.245 |
| `hash_join` | **28.311** | 30.331 | 29.950 | 3396.784 | 8381.695 |
| `sieve` | 18.361 | 18.142 | **18.042** | 64.896 | 3322.486 |
| `fib` | **25.278** | 30.039 | 28.245 | 130.266 | 1348.467 |
| `collatz` | 12.431 | **12.405** | 12.536 | 47.584 | 711.347 |
| `matmul` | 33.662 | **33.548** | 33.665 | 75.103 | 2990.205 |
| `json_parse` | **8.420** | 8.852 | 11.713 | 34.686 | 37.101 |
| `nbody` | 40.840 | 40.896 | **39.043** | 98.536 | 3007.309 |

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
| _(floor: empty program)_ | _3.007_ | _79.178_ | _**82.185**_ | _59.148_ | _61.835_ |
| `lcg` | 3.111 | 86.496 | **89.607** | 66.583 | 68.350 |
| `packet_classifier` | 3.220 | 85.895 | **89.115** | 67.373 | 67.568 |
| `ring_write` | 3.444 | 86.364 | **89.808** | 67.459 | 70.044 |
| `histogram_bins` | 3.615 | 93.392 | **97.007** | 73.737 | 93.509 |
| `prefix_scan` | 3.692 | 92.201 | **95.893** | 73.142 | 72.177 |
| `binary_search` | 3.935 | 91.686 | **95.621** | 70.031 | 74.675 |
| `sort_window` | 4.039 | 99.087 | **103.126** | 78.011 | 80.712 |
| `bloom_filter` | 4.259 | 96.000 | **100.259** | 75.923 | 74.218 |
| `hash_join` | 8.662 | 212.337 | **220.999** | 121.090 | 112.848 |
| `sieve` | 3.794 | 90.416 | **94.210** | 80.643 | 80.416 |
| `fib` | 3.161 | 81.234 | **84.395** | 65.121 | 66.222 |
| `collatz` | 3.495 | 84.977 | **88.472** | 66.027 | 69.917 |
| `matmul` | 4.332 | 92.326 | **96.658** | 78.533 | 90.170 |
| `json_parse` | 73.768 | 717.676 | **791.444** | 121.797 | 175.645 |
| `nbody` | 6.601 | 102.834 | **109.435** | 94.155 | 92.746 |

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
