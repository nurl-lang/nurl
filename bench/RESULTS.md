# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-27T18:55:06Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `220fe3b71b050a17ad2a7d5122091ac50fe90c4c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30294717011 |
| NURL | `v0.27.0-4-g220fe3b` |
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
| _(floor: empty program)_ | _1.741_ | _1.758_ | _1.905_ | _24.454_ | _17.549_ |
| `lcg` | **39.306** | 39.455 | 39.742 | 1876.271 | 5065.439 |
| `affine_mix` | **39.436** | 39.505 | 39.765 | 1868.351 | 6345.308 |
| `packet_classifier` | **56.752** | 56.816 | 57.049 | 164.710 | 4802.268 |
| `ring_write` | **42.581** | 42.827 | 42.853 | 69.034 | 6105.687 |
| `histogram_bins` | 40.093 | 41.778 | **40.006** | 67.746 | 6171.224 |
| `prefix_scan` | 22.311 | 22.240 | **22.215** | 67.844 | 4618.950 |
| `binary_search` | 40.245 | **38.845** | 43.632 | 108.829 | 6287.938 |
| `sort_window` | 27.626 | 27.899 | **27.512** | 200.572 | 11345.280 |
| `bloom_filter` | **18.303** | 18.631 | 18.799 | 2832.280 | 7543.209 |
| `hash_join` | **4.648** | 4.878 | 5.282 | 377.711 | 835.450 |
| `sieve` | 21.143 | **19.496** | 19.811 | 70.985 | 3241.570 |
| `fib` | **25.582** | 30.058 | 28.614 | 134.349 | 1346.082 |
| `collatz` | **12.563** | 12.609 | 12.842 | 52.675 | 713.890 |
| `matmul` | 34.509 | 34.435 | **34.340** | 78.892 | 3186.466 |
| `json_parse` | **8.851** | 9.158 | 11.978 | 38.903 | 40.849 |

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
| _(floor: empty program)_ | _3.097_ | _83.244_ | _**86.341**_ | _63.693_ | _64.397_ |
| `lcg` | 3.136 | 89.340 | **92.476** | 68.674 | 69.887 |
| `affine_mix` | 3.263 | 95.783 | **99.046** | 75.213 | 76.759 |
| `packet_classifier` | 3.302 | 89.654 | **92.956** | 70.107 | 72.802 |
| `ring_write` | 3.412 | 93.866 | **97.278** | 74.716 | 74.275 |
| `histogram_bins` | 3.660 | 97.737 | **101.397** | 76.966 | 79.933 |
| `prefix_scan` | 3.628 | 93.117 | **96.745** | 77.106 | 76.550 |
| `binary_search` | 4.179 | 99.896 | **104.075** | 75.854 | 82.529 |
| `sort_window` | 4.176 | 105.352 | **109.528** | 80.562 | 84.083 |
| `bloom_filter` | 4.216 | 102.877 | **107.093** | 81.946 | 83.942 |
| `hash_join` | 9.054 | 221.633 | **230.687** | 127.387 | 122.972 |
| `sieve` | 3.803 | 101.415 | **105.218** | 87.312 | 91.282 |
| `fib` | 3.100 | 91.152 | **94.252** | 74.162 | 71.934 |
| `collatz` | 3.465 | 94.280 | **97.745** | 72.703 | 76.855 |
| `matmul` | 4.678 | 102.431 | **107.109** | 86.996 | 99.891 |
| `json_parse` | 74.143 | 765.723 | **839.866** | 131.337 | 194.248 |

## 3. Correctness gate

Each row is timed only when all five implementations print the same
line. A speed number for a program computing something else is worthless,
so a mismatch drops the row out of the tables above rather than being
reported as a fast cell.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical across 5 languages |
| `affine_mix` | `227901546981696845` | identical across 5 languages |
| `packet_classifier` | `4205972061` | identical across 5 languages |
| `ring_write` | `8299504528805184357` | identical across 5 languages |
| `histogram_bins` | `1215643728` | identical across 5 languages |
| `prefix_scan` | `492982549` | identical across 5 languages |
| `binary_search` | `805907445` | identical across 5 languages |
| `sort_window` | `2815490238` | identical across 5 languages |
| `bloom_filter` | `2351703` | identical across 5 languages |
| `hash_join` | `2814341850483607168` | identical across 5 languages |
| `sieve` | `664579` | identical across 5 languages |
| `fib` | `9227465` | identical across 5 languages |
| `collatz` | `350` | identical across 5 languages |
| `matmul` | `393199` | identical across 5 languages |
| `json_parse` | `20` | identical across 5 languages |

## 4. Reading the numbers

* A cell near the floor row is mostly process start-up, dynamic linking
  and page faults rather than the benchmark. The rows worth comparing are
  the ones in the tens of milliseconds and up.
* All three compiled back ends are LLVM-based and all three are allowed to
  be clever: LLVM will fold an affine recurrence or unroll a loop by a
  different factor in each language. A cell measures optimised throughput
  of the same algorithm, not the source-level iteration count.
* Ten of the fifteen benchmarks are defined over 64-bit unsigned integers.
  Python has arbitrary-precision integers and masks; JS has no 64-bit
  integer at all, so those rows use `BigInt` where the algorithm genuinely
  needs 64 bits and Numbers with `Math.imul` where 32 bits suffice. Each
  file says which and why. That gap *is* part of what this table reports.
* `json_parse` is the one row whose gate is "every parser accepted the
  document" rather than a structural checksum: each language uses the
  parser in its own box (Python `json`, Node `JSON.parse`, NURL
  `stdlib/ext/json.nu`), and C and Rust — whose boxes are empty — carry a
  small hand-written recursive-descent parser in the benchmark file.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
