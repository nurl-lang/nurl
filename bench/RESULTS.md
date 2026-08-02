# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-02T21:33:24Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `08cba87073891e34a503141799956aa47683500a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30767977516 |
| NURL | `v0.31.0-3-g08cba870` |
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
| _(floor: empty program)_ | _1.662_ | _1.701_ | _1.855_ | _22.849_ | _17.165_ |
| `lcg` | **39.253** | 39.331 | 39.448 | 1874.238 | 5108.661 |
| `packet_classifier` | **56.425** | 56.574 | 56.627 | 161.749 | 4493.966 |
| `ring_write` | 42.545 | **42.392** | 42.429 | 65.218 | 6234.841 |
| `histogram_bins` | **39.878** | 41.453 | 39.969 | 65.395 | 6396.898 |
| `prefix_scan` | 21.981 | **21.975** | 22.071 | 65.037 | 4588.531 |
| `binary_search` | 39.969 | **38.236** | 43.272 | 106.408 | 6017.662 |
| `sort_window` | 27.503 | 27.495 | **27.076** | 196.899 | 12191.849 |
| `bloom_filter` | **17.972** | 18.233 | 18.499 | 2838.258 | 7495.833 |
| `hash_join` | **28.371** | 30.217 | 30.174 | 3408.888 | 8355.425 |
| `sieve` | 18.547 | 18.244 | **18.040** | 66.015 | 3246.730 |
| `fib` | **25.333** | 30.020 | 28.252 | 135.689 | 1334.768 |
| `collatz` | **12.408** | 12.500 | 12.557 | 51.673 | 706.620 |
| `matmul` | 33.561 | **33.459** | 33.843 | 75.462 | 3238.867 |
| `json_parse` | **8.587** | 8.853 | 11.790 | 35.070 | 37.499 |
| `nbody` | 41.154 | 41.087 | **39.164** | 102.652 | 3077.176 |

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
| _(floor: empty program)_ | _2.611_ | _79.216_ | _**81.827**_ | _55.558_ | _61.438_ |
| `lcg` | 2.699 | 83.389 | **86.088** | 66.358 | 68.912 |
| `packet_classifier` | 2.824 | 87.383 | **90.207** | 66.830 | 68.381 |
| `ring_write` | 2.841 | 85.676 | **88.517** | 67.698 | 73.667 |
| `histogram_bins` | 2.910 | 87.821 | **90.731** | 68.821 | 71.803 |
| `prefix_scan` | 2.979 | 91.198 | **94.177** | 72.164 | 71.203 |
| `binary_search` | 3.066 | 89.163 | **92.229** | 68.183 | 74.814 |
| `sort_window` | 3.118 | 94.360 | **97.478** | 73.486 | 77.678 |
| `bloom_filter` | 3.254 | 95.014 | **98.268** | 75.159 | 75.096 |
| `hash_join` | 5.322 | 206.847 | **212.169** | 121.341 | 110.783 |
| `sieve` | 2.985 | 88.683 | **91.668** | 78.504 | 79.174 |
| `fib` | 2.729 | 83.683 | **86.412** | 64.936 | 66.065 |
| `collatz` | 2.917 | 87.062 | **89.979** | 66.049 | 69.412 |
| `matmul` | 3.191 | 93.669 | **96.860** | 80.108 | 91.898 |
| `json_parse` | 40.095 | 517.029 | **557.124** | 122.687 | 177.660 |
| `nbody` | 4.233 | 105.545 | **109.778** | 95.694 | 92.410 |

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
