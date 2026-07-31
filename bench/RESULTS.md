# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-31T07:46:45Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `d2c2f76ee7919b6606dafcf1ba02302e67d69567` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30613691826 |
| NURL | `v0.29.0-77-gd2c2f76` |
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
| _(floor: empty program)_ | _1.696_ | _1.713_ | _1.850_ | _23.267_ | _17.909_ |
| `lcg` | **39.239** | 39.261 | 39.484 | 1882.769 | 5957.568 |
| `packet_classifier` | **56.427** | 56.693 | 56.678 | 163.426 | 4382.738 |
| `ring_write` | **42.388** | 42.496 | 42.726 | 68.133 | 6218.112 |
| `histogram_bins` | **39.685** | 41.445 | 39.906 | 66.769 | 6131.035 |
| `prefix_scan` | **22.002** | 22.118 | 22.250 | 66.748 | 4596.674 |
| `binary_search` | 40.029 | **38.413** | 43.313 | 107.783 | 6376.248 |
| `sort_window` | 27.526 | 27.540 | **27.079** | 198.744 | 11685.015 |
| `bloom_filter` | **18.248** | 18.561 | 18.809 | 2846.564 | 7316.301 |
| `hash_join` | **28.183** | 30.280 | 30.350 | 3435.954 | 9123.876 |
| `sieve` | 19.285 | **18.359** | 18.676 | 66.759 | 3212.952 |
| `fib` | **25.324** | 30.028 | 28.394 | 131.884 | 1353.047 |
| `collatz` | **12.482** | 12.517 | 12.681 | 50.843 | 713.927 |
| `matmul` | **33.661** | 33.878 | 34.110 | 79.233 | 3409.816 |
| `json_parse` | **8.560** | 8.915 | 11.895 | 37.660 | 38.044 |
| `nbody` | 41.190 | 41.217 | **39.375** | 104.447 | 3092.135 |

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
| _(floor: empty program)_ | _3.113_ | _82.851_ | _**85.964**_ | _59.908_ | _61.227_ |
| `lcg` | 3.210 | 89.224 | **92.434** | 71.237 | 71.348 |
| `packet_classifier` | 3.298 | 88.717 | **92.015** | 68.965 | 68.681 |
| `ring_write` | 3.536 | 88.319 | **91.855** | 68.817 | 70.359 |
| `histogram_bins` | 3.655 | 91.947 | **95.602** | 70.088 | 71.683 |
| `prefix_scan` | 3.704 | 95.537 | **99.241** | 74.765 | 73.601 |
| `binary_search` | 3.964 | 93.772 | **97.736** | 71.774 | 74.659 |
| `sort_window` | 4.156 | 101.346 | **105.502** | 79.563 | 79.841 |
| `bloom_filter` | 4.324 | 99.168 | **103.492** | 78.546 | 82.604 |
| `hash_join` | 8.852 | 213.012 | **221.864** | 118.991 | 113.248 |
| `sieve` | 3.678 | 90.620 | **94.298** | 78.144 | 78.213 |
| `fib` | 3.205 | 88.570 | **91.775** | 69.263 | 67.212 |
| `collatz` | 3.571 | 91.129 | **94.700** | 71.804 | 69.919 |
| `matmul` | 4.397 | 99.369 | **103.766** | 83.869 | 93.546 |
| `json_parse` | 74.939 | 763.108 | **838.047** | 128.580 | 176.215 |
| `nbody` | 6.720 | 111.149 | **117.869** | 99.588 | 93.855 |

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
