# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-12T14:17:10Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373456 KiB |
| Commit | `e1e4efa529b9ca78d40728c17787e04c0975eb6c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31605490475 |
| NURL | `v0.39.0-6-ge1e4efa5` |
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
| _(floor: empty program)_ | _1.998_ | _2.029_ | _2.212_ | _27.417_ | _20.441_ |
| `lcg` | **44.577** | 44.733 | 44.851 | 1867.707 | 5979.476 |
| `packet_classifier` | **63.942** | 64.164 | 64.189 | 160.928 | 4675.040 |
| `ring_write` | **48.204** | 48.260 | 48.344 | 75.842 | 6520.271 |
| `histogram_bins` | **45.123** | 45.187 | 45.340 | 77.748 | 6259.845 |
| `prefix_scan` | **24.946** | 25.018 | 25.205 | 74.493 | 4808.580 |
| `binary_search` | **36.094** | 36.149 | 46.567 | 112.969 | 6538.463 |
| `sort_window` | 31.203 | 31.219 | **30.808** | 167.289 | 12455.395 |
| `bloom_filter` | **20.204** | 20.864 | 21.258 | 2756.430 | 7995.951 |
| `hash_join` | **29.572** | 31.154 | 31.619 | 3405.356 | 8189.464 |
| `sieve` | 21.342 | **21.008** | 21.073 | 73.256 | 3471.161 |
| `fib` | **28.349** | 33.761 | 29.911 | 143.962 | 1290.781 |
| `collatz` | **14.125** | 14.250 | 14.335 | 54.642 | 754.840 |
| `matmul` | **44.877** | 46.229 | 46.457 | 85.992 | 3516.955 |
| `json_parse` | **9.031** | 9.452 | 12.817 | 41.232 | 40.192 |
| `nbody` | 46.586 | 46.653 | **44.402** | 97.428 | 3259.255 |

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
| _(floor: empty program)_ | _3.296_ | _99.014_ | _**102.310**_ | _69.745_ | _70.552_ |
| `lcg` | 3.330 | 103.497 | **106.827** | 79.322 | 79.279 |
| `packet_classifier` | 3.506 | 104.812 | **108.318** | 80.434 | 79.118 |
| `ring_write` | 3.489 | 103.893 | **107.382** | 80.465 | 81.543 |
| `histogram_bins` | 3.764 | 109.918 | **113.682** | 83.580 | 83.402 |
| `prefix_scan` | 3.730 | 110.433 | **114.163** | 84.625 | 83.067 |
| `binary_search` | 3.792 | 109.513 | **113.305** | 82.016 | 86.055 |
| `sort_window` | 3.884 | 116.594 | **120.478** | 88.030 | 92.030 |
| `bloom_filter` | 4.003 | 112.585 | **116.588** | 88.355 | 85.777 |
| `hash_join` | 6.369 | 219.712 | **226.081** | 129.012 | 124.074 |
| `sieve` | 3.601 | 109.174 | **112.775** | 90.041 | 91.114 |
| `fib` | 3.296 | 101.969 | **105.265** | 78.615 | 77.023 |
| `collatz` | 3.495 | 106.216 | **109.711** | 80.216 | 80.901 |
| `matmul` | 3.806 | 112.620 | **116.426** | 91.271 | 104.382 |
| `json_parse` | 44.938 | 546.698 | **591.636** | 132.176 | 200.499 |
| `nbody` | 5.019 | 123.147 | **128.166** | 106.099 | 104.569 |

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
