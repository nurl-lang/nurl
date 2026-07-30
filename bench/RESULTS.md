# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T12:24:59Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `93a8cada4ff3c600ac58781883a5b68e898d8c5b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30542092108 |
| NURL | `v0.29.0-22-g93a8cad` |
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
| _(floor: empty program)_ | _1.695_ | _1.749_ | _1.959_ | _24.002_ | _18.355_ |
| `lcg` | **39.537** | 39.640 | 39.787 | 1893.065 | 5136.547 |
| `packet_classifier` | **56.756** | 56.882 | 57.067 | 164.040 | 4499.981 |
| `ring_write` | **42.623** | 42.760 | 42.891 | 68.935 | 6518.828 |
| `histogram_bins` | **39.990** | 41.670 | 40.239 | 68.540 | 6054.211 |
| `prefix_scan` | **21.998** | 22.207 | 22.266 | 67.089 | 4619.244 |
| `binary_search` | 40.282 | **38.872** | 43.922 | 107.829 | 6208.874 |
| `sort_window` | 27.398 | 27.492 | **27.092** | 198.252 | 11831.107 |
| `bloom_filter` | **18.119** | 18.530 | 18.519 | 2850.256 | 7869.776 |
| `hash_join` | **28.452** | 30.720 | 30.467 | 3430.108 | 8169.151 |
| `sieve` | 19.758 | 19.063 | **19.002** | 68.870 | 3297.015 |
| `fib` | **25.566** | 30.351 | 28.593 | 133.251 | 1342.168 |
| `collatz` | **12.546** | 12.602 | 12.684 | 50.370 | 716.344 |
| `matmul` | **34.114** | 34.244 | 34.427 | 76.632 | 3050.534 |
| `json_parse` | **8.934** | 9.281 | 12.059 | 38.336 | 40.551 |
| `nbody` | 41.572 | 41.341 | **39.534** | 103.444 | 3079.162 |

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
| _(floor: empty program)_ | _3.435_ | _84.250_ | _**87.685**_ | _60.641_ | _64.476_ |
| `lcg` | 3.266 | 87.542 | **90.808** | 68.696 | 70.059 |
| `packet_classifier` | 3.433 | 92.301 | **95.734** | 72.694 | 74.618 |
| `ring_write` | 3.604 | 92.575 | **96.179** | 72.648 | 75.218 |
| `histogram_bins` | 3.684 | 96.263 | **99.947** | 74.058 | 76.937 |
| `prefix_scan` | 3.725 | 94.421 | **98.146** | 75.235 | 73.621 |
| `binary_search` | 4.050 | 95.784 | **99.834** | 73.979 | 77.191 |
| `sort_window` | 4.137 | 102.260 | **106.397** | 79.436 | 82.580 |
| `bloom_filter` | 4.457 | 101.044 | **105.501** | 81.775 | 79.296 |
| `hash_join` | 8.968 | 217.007 | **225.975** | 125.000 | 114.622 |
| `sieve` | 3.850 | 96.678 | **100.528** | 81.676 | 84.314 |
| `fib` | 3.325 | 89.987 | **93.312** | 69.884 | 70.362 |
| `collatz` | 3.677 | 95.495 | **99.172** | 70.565 | 71.107 |
| `matmul` | 4.399 | 102.743 | **107.142** | 86.218 | 100.309 |
| `json_parse` | 74.923 | 747.203 | **822.126** | 128.916 | 187.603 |
| `nbody` | 7.044 | 116.742 | **123.786** | 101.804 | 99.019 |

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
