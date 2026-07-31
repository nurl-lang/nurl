# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-31T05:41:14Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `52becfce89cb04ea2f2882b37e49777e04f3e49e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30607247482 |
| NURL | `v0.29.0-71-g52becfc` |
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
| _(floor: empty program)_ | _1.664_ | _1.713_ | _1.882_ | _22.451_ | _16.851_ |
| `lcg` | **39.165** | 39.331 | 39.469 | 1878.045 | 5246.114 |
| `packet_classifier` | **56.500** | 56.645 | 56.627 | 161.782 | 4357.497 |
| `ring_write` | **42.460** | 42.474 | 42.577 | 66.524 | 6327.111 |
| `histogram_bins` | **39.651** | 41.403 | 39.951 | 66.764 | 6009.750 |
| `prefix_scan` | **21.922** | 21.930 | 22.064 | 65.390 | 4426.057 |
| `binary_search` | 39.993 | **38.583** | 43.297 | 107.408 | 6605.067 |
| `sort_window` | 27.618 | 27.401 | **26.939** | 198.393 | 11501.529 |
| `bloom_filter` | **18.080** | 18.287 | 18.547 | 2880.818 | 7633.999 |
| `hash_join` | **28.182** | 30.372 | 30.131 | 3427.868 | 8651.537 |
| `sieve` | 20.267 | 18.687 | **18.237** | 65.943 | 3291.661 |
| `fib` | **25.242** | 30.152 | 28.427 | 131.079 | 1347.918 |
| `collatz` | **12.475** | 12.477 | 12.569 | 49.187 | 710.857 |
| `matmul` | 33.888 | 33.925 | **33.877** | 76.932 | 3299.869 |
| `json_parse` | **8.485** | 8.775 | 11.743 | 35.321 | 37.224 |
| `nbody` | 40.894 | 40.948 | **39.140** | 100.164 | 3017.908 |

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
| _(floor: empty program)_ | _3.074_ | _77.767_ | _**80.841**_ | _64.824_ | _59.488_ |
| `lcg` | 3.117 | 84.097 | **87.214** | 65.425 | 68.073 |
| `packet_classifier` | 3.219 | 84.378 | **87.597** | 67.535 | 67.563 |
| `ring_write` | 3.569 | 86.878 | **90.447** | 68.129 | 69.358 |
| `histogram_bins` | 3.760 | 91.153 | **94.913** | 71.215 | 71.038 |
| `prefix_scan` | 3.640 | 90.843 | **94.483** | 73.245 | 71.534 |
| `binary_search` | 3.962 | 91.986 | **95.948** | 69.514 | 73.952 |
| `sort_window` | 4.049 | 96.340 | **100.389** | 74.487 | 78.611 |
| `bloom_filter` | 4.297 | 95.599 | **99.896** | 76.239 | 78.151 |
| `hash_join` | 8.722 | 208.866 | **217.588** | 119.081 | 107.209 |
| `sieve` | 3.810 | 92.664 | **96.474** | 78.692 | 77.739 |
| `fib` | 3.109 | 82.853 | **85.962** | 66.340 | 65.721 |
| `collatz` | 3.478 | 87.626 | **91.104** | 67.936 | 69.335 |
| `matmul` | 4.384 | 95.484 | **99.868** | 80.000 | 90.728 |
| `json_parse` | 73.167 | 721.122 | **794.289** | 123.452 | 175.354 |
| `nbody` | 6.691 | 106.693 | **113.384** | 95.450 | 91.576 |

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
