# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T05:58:58Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373460 KiB |
| Commit | `b270c0f0c35e900605d3216b7933b845701d7b73` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31463202854 |
| NURL | `v0.37.0` |
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
| _(floor: empty program)_ | _1.645_ | _1.719_ | _1.873_ | _22.978_ | _16.934_ |
| `lcg` | 39.374 | **39.367** | 39.547 | 1874.599 | 5117.396 |
| `packet_classifier` | **56.502** | 56.675 | 56.747 | 161.330 | 4298.285 |
| `ring_write` | **42.497** | 42.586 | 42.765 | 67.648 | 6249.505 |
| `histogram_bins` | **39.964** | 41.523 | 40.051 | 66.646 | 6006.674 |
| `prefix_scan` | 22.035 | **22.001** | 22.177 | 64.840 | 4414.625 |
| `binary_search` | 40.004 | **38.675** | 43.554 | 106.675 | 5943.449 |
| `sort_window` | 27.435 | 27.499 | **26.930** | 198.059 | 11269.813 |
| `bloom_filter` | **18.092** | 18.486 | 18.824 | 2824.838 | 7382.982 |
| `hash_join` | **28.198** | 30.236 | 30.173 | 3406.945 | 8331.608 |
| `sieve` | 20.938 | 20.737 | **20.650** | 69.669 | 3494.242 |
| `fib` | **25.504** | 30.289 | 28.627 | 132.257 | 1348.760 |
| `collatz` | 12.679 | **12.618** | 12.755 | 51.112 | 709.151 |
| `matmul` | 33.956 | **33.950** | 34.194 | 77.215 | 3159.639 |
| `json_parse` | 42.344 | **8.919** | 11.688 | 36.386 | 37.108 |
| `nbody` | 40.882 | 41.117 | **39.112** | 102.879 | 3020.380 |

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
| _(floor: empty program)_ | _3.042_ | _81.091_ | _**84.133**_ | _57.881_ | _59.907_ |
| `lcg` | 2.772 | 83.281 | **86.053** | 64.798 | 67.887 |
| `packet_classifier` | 2.830 | 86.933 | **89.763** | 67.500 | 67.734 |
| `ring_write` | 2.966 | 88.855 | **91.821** | 68.409 | 70.003 |
| `histogram_bins` | 2.979 | 94.139 | **97.118** | 72.417 | 73.162 |
| `prefix_scan` | 3.052 | 93.301 | **96.353** | 71.015 | 71.906 |
| `binary_search` | 3.229 | 91.884 | **95.113** | 69.049 | 74.139 |
| `sort_window` | 3.225 | 99.112 | **102.337** | 75.529 | 79.422 |
| `bloom_filter` | 3.492 | 98.094 | **101.586** | 77.496 | 73.932 |
| `hash_join` | 5.654 | 213.863 | **219.517** | 120.686 | 109.578 |
| `sieve` | 3.156 | 97.555 | **100.711** | 81.993 | 80.360 |
| `fib` | 2.894 | 87.355 | **90.249** | 68.593 | 67.381 |
| `collatz` | 3.127 | 93.962 | **97.089** | 70.838 | 71.450 |
| `matmul` | 3.291 | 99.033 | **102.324** | 83.568 | 94.140 |
| `json_parse` | 42.793 | 540.718 | **583.511** | 122.785 | 175.740 |
| `nbody` | 4.395 | 106.665 | **111.060** | 95.669 | 92.147 |

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
