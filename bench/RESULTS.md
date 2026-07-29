# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-29T20:45:39Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `476720b28b247d617a7999b1c65f43dfe2d25cc5` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30489380724 |
| NURL | `v0.28.0-3-g476720b` |
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
| _(floor: empty program)_ | _1.781_ | _1.876_ | _2.031_ | _24.210_ | _17.952_ |
| `lcg` | **44.253** | 44.310 | 44.543 | 1834.708 | 5505.043 |
| `packet_classifier` | **63.768** | 63.844 | 63.944 | 158.741 | 4692.291 |
| `ring_write` | **47.834** | 47.978 | 48.074 | 73.143 | 6603.992 |
| `histogram_bins` | **44.839** | 44.909 | 45.020 | 74.592 | 6923.518 |
| `prefix_scan` | **24.691** | 24.773 | 24.874 | 72.401 | 5165.170 |
| `binary_search` | **35.863** | 35.883 | 46.201 | 114.780 | 6400.627 |
| `sort_window` | 30.795 | 31.019 | **30.396** | 166.716 | 11520.950 |
| `bloom_filter` | **19.926** | 20.589 | 20.900 | 2853.217 | 8183.283 |
| `hash_join` | **29.425** | 30.917 | 31.255 | 3436.555 | 8172.681 |
| `sieve` | 20.586 | **20.230** | 20.287 | 70.651 | 3346.791 |
| `fib` | **28.173** | 33.506 | 29.528 | 142.781 | 1287.691 |
| `collatz` | **13.924** | 13.941 | 14.073 | 51.215 | 760.828 |
| `matmul` | **45.147** | 46.402 | 46.480 | 82.995 | 3547.999 |
| `json_parse` | **8.535** | 9.044 | 12.415 | 37.682 | 38.249 |
| `nbody` | 46.966 | 46.460 | **44.713** | 97.082 | 3231.809 |

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
| _(floor: empty program)_ | _3.220_ | _89.353_ | _**92.573**_ | _66.049_ | _65.885_ |
| `lcg` | 3.445 | 92.739 | **96.184** | 72.636 | 73.417 |
| `packet_classifier` | 3.525 | 93.866 | **97.391** | 73.238 | 74.427 |
| `ring_write` | 3.799 | 95.394 | **99.193** | 86.223 | 84.871 |
| `histogram_bins` | 3.874 | 98.434 | **102.308** | 76.702 | 78.045 |
| `prefix_scan` | 4.066 | 99.517 | **103.583** | 78.582 | 99.431 |
| `binary_search` | 4.332 | 98.445 | **102.777** | 76.372 | 81.452 |
| `sort_window` | 4.371 | 104.852 | **109.223** | 82.019 | 84.456 |
| `bloom_filter` | 4.609 | 103.603 | **108.212** | 82.337 | 81.425 |
| `hash_join` | 9.617 | 208.400 | **218.017** | 122.482 | 116.103 |
| `sieve` | 4.000 | 100.249 | **104.249** | 83.701 | 85.350 |
| `fib` | 3.385 | 92.187 | **95.572** | 72.754 | 72.286 |
| `collatz` | 3.763 | 95.751 | **99.514** | 75.320 | 76.225 |
| `matmul` | 4.860 | 102.953 | **107.813** | 85.096 | 97.929 |
| `json_parse` | 77.734 | 696.304 | **774.038** | 128.182 | 188.552 |
| `nbody` | 8.022 | 113.814 | **121.836** | 100.885 | 99.828 |

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
