# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-03T16:02:56Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `cf51a1ba710f7fb25efac61604d6dc5bb4155be8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30829979677 |
| NURL | `v0.32.0-13-gcf51a1ba` |
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
| _(floor: empty program)_ | _1.780_ | _1.887_ | _2.037_ | _24.889_ | _18.138_ |
| `lcg` | **44.405** | 44.425 | 44.636 | 1834.086 | 5648.147 |
| `packet_classifier` | **63.864** | 63.894 | 64.020 | 158.505 | 4556.413 |
| `ring_write` | **47.996** | 48.028 | 48.139 | 74.736 | 7222.901 |
| `histogram_bins` | 44.935 | **44.874** | 45.034 | 77.500 | 6372.380 |
| `prefix_scan` | 24.820 | **24.817** | 25.040 | 75.073 | 4665.769 |
| `binary_search` | **35.938** | 36.226 | 46.470 | 112.860 | 7118.837 |
| `sort_window` | 30.919 | 31.059 | **30.458** | 167.424 | 12311.210 |
| `bloom_filter` | **19.939** | 20.553 | 20.896 | 2723.015 | 7989.917 |
| `hash_join` | **29.311** | 31.154 | 31.158 | 3406.165 | 8207.487 |
| `sieve` | 20.986 | **20.887** | 21.062 | 73.518 | 3444.943 |
| `fib` | **28.257** | 33.641 | 29.822 | 143.555 | 1296.372 |
| `collatz` | **13.932** | 13.956 | 14.124 | 54.064 | 754.568 |
| `matmul` | 45.794 | 46.541 | **45.335** | 84.236 | 3320.904 |
| `json_parse` | **8.517** | 9.224 | 12.519 | 40.119 | 39.261 |
| `nbody` | 46.406 | 46.404 | **44.348** | 96.740 | 3213.417 |

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
| _(floor: empty program)_ | _2.964_ | _91.249_ | _**94.213**_ | _64.918_ | _66.281_ |
| `lcg` | 3.069 | 95.467 | **98.536** | 75.749 | 74.266 |
| `packet_classifier` | 3.157 | 97.072 | **100.229** | 75.631 | 74.546 |
| `ring_write` | 3.232 | 98.982 | **102.214** | 77.261 | 77.317 |
| `histogram_bins` | 3.308 | 102.558 | **105.866** | 80.200 | 79.675 |
| `prefix_scan` | 3.449 | 102.821 | **106.270** | 80.860 | 79.581 |
| `binary_search` | 3.483 | 103.326 | **106.809** | 77.289 | 84.377 |
| `sort_window` | 3.503 | 109.053 | **112.556** | 85.270 | 85.981 |
| `bloom_filter` | 3.689 | 105.904 | **109.593** | 83.244 | 82.052 |
| `hash_join` | 5.766 | 210.916 | **216.682** | 123.233 | 117.182 |
| `sieve` | 3.412 | 105.144 | **108.556** | 87.528 | 93.118 |
| `fib` | 3.078 | 96.957 | **100.035** | 75.925 | 75.027 |
| `collatz` | 3.349 | 101.072 | **104.421** | 76.142 | 76.918 |
| `matmul` | 3.667 | 109.034 | **112.701** | 90.304 | 104.826 |
| `json_parse` | 40.095 | 503.120 | **543.215** | 127.075 | 190.194 |
| `nbody` | 4.624 | 118.471 | **123.095** | 103.194 | 105.445 |

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
