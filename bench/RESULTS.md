# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-08T15:17:33Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `2f8baf2a863698f38245cc3e5ba3aed7bfccb009` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31263883755 |
| NURL | `v0.35.1-44-g2f8baf2a` |
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
| _(floor: empty program)_ | _1.698_ | _1.739_ | _1.876_ | _23.186_ | _17.357_ |
| `lcg` | **39.410** | 39.417 | 39.541 | 1873.897 | 5463.932 |
| `packet_classifier` | **56.343** | 56.402 | 56.494 | 162.498 | 4552.051 |
| `ring_write` | **42.376** | 42.477 | 42.504 | 66.613 | 6204.806 |
| `histogram_bins` | **39.827** | 41.551 | 40.075 | 66.989 | 6015.993 |
| `prefix_scan` | 21.931 | **21.924** | 22.116 | 66.401 | 4827.090 |
| `binary_search` | 39.924 | **38.600** | 43.424 | 107.080 | 6060.739 |
| `sort_window` | 27.583 | 27.628 | **27.144** | 197.671 | 11314.275 |
| `bloom_filter` | **18.234** | 18.536 | 18.811 | 2824.547 | 7482.057 |
| `hash_join` | **28.079** | 30.164 | 30.016 | 3432.620 | 8144.333 |
| `sieve` | 20.927 | **20.520** | 20.671 | 68.716 | 3310.685 |
| `fib` | **25.354** | 30.041 | 28.390 | 132.357 | 1374.508 |
| `collatz` | 12.498 | **12.465** | 12.542 | 48.558 | 711.345 |
| `matmul` | 33.611 | **33.575** | 33.744 | 78.011 | 3131.774 |
| `json_parse` | 42.673 | **8.910** | 11.839 | 36.294 | 37.905 |
| `nbody` | 41.058 | 41.574 | **39.319** | 100.640 | 3019.436 |

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
| _(floor: empty program)_ | _2.633_ | _81.102_ | _**83.735**_ | _58.077_ | _104.902_ |
| `lcg` | 2.975 | 90.660 | **93.635** | 67.775 | 68.037 |
| `packet_classifier` | 2.855 | 89.765 | **92.620** | 68.321 | 68.109 |
| `ring_write` | 3.000 | 90.577 | **93.577** | 69.499 | 70.494 |
| `histogram_bins` | 3.026 | 94.180 | **97.206** | 72.162 | 73.991 |
| `prefix_scan` | 3.046 | 96.107 | **99.153** | 74.343 | 73.384 |
| `binary_search` | 3.184 | 93.226 | **96.410** | 71.960 | 75.661 |
| `sort_window` | 3.227 | 100.326 | **103.553** | 76.768 | 79.627 |
| `bloom_filter` | 3.450 | 101.235 | **104.685** | 79.733 | 76.583 |
| `hash_join` | 5.422 | 214.948 | **220.370** | 122.874 | 112.922 |
| `sieve` | 3.080 | 95.078 | **98.158** | 80.343 | 80.261 |
| `fib` | 2.828 | 87.344 | **90.172** | 67.338 | 70.387 |
| `collatz` | 2.929 | 87.630 | **90.559** | 67.705 | 69.671 |
| `matmul` | 3.255 | 95.832 | **99.087** | 79.457 | 92.998 |
| `json_parse` | 41.030 | 553.599 | **594.629** | 130.765 | 181.270 |
| `nbody` | 4.374 | 109.053 | **113.427** | 97.404 | 95.441 |

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
