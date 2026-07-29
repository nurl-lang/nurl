# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-29T09:55:13Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `d7b25b6616fe181a57321f73865d531bf75f4ef3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30441249457 |
| NURL | `v0.27.0-55-gd7b25b6` |
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
| _(floor: empty program)_ | _1.786_ | _1.862_ | _1.993_ | _23.470_ | _17.754_ |
| `lcg` | **44.278** | 44.372 | 44.485 | 1829.671 | 5331.876 |
| `packet_classifier` | **63.707** | 63.823 | 64.014 | 159.183 | 4732.399 |
| `ring_write` | **47.831** | 47.923 | 47.999 | 74.574 | 6424.182 |
| `histogram_bins` | **44.777** | 44.913 | 44.940 | 74.930 | 6331.837 |
| `prefix_scan` | **24.693** | 24.762 | 26.931 | 73.007 | 4762.409 |
| `binary_search` | 36.043 | **35.916** | 46.279 | 111.351 | 6371.561 |
| `sort_window` | 30.920 | 30.955 | **30.423** | 166.151 | 11754.223 |
| `bloom_filter` | **19.957** | 20.591 | 20.875 | 2904.601 | 7923.968 |
| `hash_join` | **29.430** | 31.093 | 31.430 | 3459.959 | 8296.932 |
| `sieve` | 20.820 | **20.320** | 20.473 | 72.474 | 3608.695 |
| `fib` | **28.129** | 33.435 | 29.567 | 144.974 | 1290.405 |
| `collatz` | 13.937 | **13.912** | 14.059 | 52.725 | 750.803 |
| `matmul` | **45.553** | 46.791 | 46.265 | 84.974 | 3739.245 |
| `json_parse` | **8.431** | 9.141 | 12.329 | 38.839 | 38.918 |
| `nbody` | 46.347 | 46.456 | **44.272** | 96.049 | 3314.145 |

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
| _(floor: empty program)_ | _3.147_ | _85.872_ | _**89.019**_ | _63.724_ | _64.917_ |
| `lcg` | 3.371 | 90.646 | **94.017** | 71.330 | 72.625 |
| `packet_classifier` | 3.562 | 92.814 | **96.376** | 75.823 | 73.217 |
| `ring_write` | 3.767 | 94.506 | **98.273** | 74.506 | 73.363 |
| `histogram_bins` | 3.937 | 98.014 | **101.951** | 76.428 | 78.138 |
| `prefix_scan` | 3.989 | 98.441 | **102.430** | 78.042 | 75.872 |
| `binary_search` | 4.239 | 99.655 | **103.894** | 73.941 | 78.884 |
| `sort_window` | 4.347 | 103.962 | **108.309** | 80.629 | 83.235 |
| `bloom_filter` | 4.653 | 104.007 | **108.660** | 82.107 | 84.872 |
| `hash_join` | 9.683 | 209.822 | **219.505** | 121.172 | 116.598 |
| `sieve` | 3.996 | 99.084 | **103.080** | 82.470 | 83.768 |
| `fib` | 3.396 | 92.896 | **96.292** | 74.540 | 73.664 |
| `collatz` | 3.769 | 97.736 | **101.505** | 75.824 | 75.223 |
| `matmul` | 4.845 | 101.791 | **106.636** | 85.934 | 97.589 |
| `json_parse` | 77.651 | 695.928 | **773.579** | 125.551 | 185.821 |
| `nbody` | 7.894 | 115.818 | **123.712** | 100.990 | 97.959 |

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
