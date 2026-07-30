# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T16:49:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `83d667415d59221ca8854e2e65ae794e94650eee` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30562846890 |
| NURL | `v0.29.0-43-g83d6674` |
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
| _(floor: empty program)_ | _1.370_ | _1.364_ | _1.479_ | _22.817_ | _16.240_ |
| `lcg` | **37.648** | 37.659 | 37.657 | 1763.999 | 5252.864 |
| `packet_classifier` | **52.773** | 52.961 | 52.984 | 157.447 | 4268.419 |
| `ring_write` | **40.614** | 40.664 | 40.936 | 70.069 | 6441.358 |
| `histogram_bins` | 40.683 | 40.708 | **39.406** | 70.344 | 6184.109 |
| `prefix_scan` | 21.439 | 21.856 | **21.009** | 68.705 | 4559.267 |
| `binary_search` | 34.184 | **30.183** | 39.799 | 105.551 | 6434.982 |
| `sort_window` | 37.507 | 45.785 | **35.748** | 181.946 | 11108.145 |
| `bloom_filter` | 14.147 | 14.580 | **13.818** | 2785.056 | 7750.836 |
| `hash_join` | **26.145** | 28.116 | 28.277 | 3374.441 | 7937.316 |
| `sieve` | 32.852 | **31.836** | 32.628 | 80.194 | 3544.496 |
| `fib` | 26.152 | 26.814 | **25.480** | 124.046 | 1163.115 |
| `collatz` | 12.939 | **12.822** | 12.900 | 57.855 | 683.280 |
| `matmul` | 17.397 | **17.297** | 17.468 | 73.301 | 2990.897 |
| `json_parse` | **7.155** | 7.745 | 9.740 | 34.101 | 35.308 |
| `nbody` | 36.071 | 36.255 | **33.439** | 92.722 | 2386.511 |

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
| _(floor: empty program)_ | _2.502_ | _71.963_ | _**74.465**_ | _53.501_ | _58.772_ |
| `lcg` | 2.558 | 75.535 | **78.093** | 57.669 | 64.807 |
| `packet_classifier` | 2.646 | 79.267 | **81.913** | 62.339 | 63.710 |
| `ring_write` | 2.668 | 78.603 | **81.271** | 63.302 | 73.378 |
| `histogram_bins` | 3.309 | 82.529 | **85.838** | 64.372 | 69.260 |
| `prefix_scan` | 2.926 | 81.844 | **84.770** | 65.114 | 68.483 |
| `binary_search` | 3.252 | 82.087 | **85.339** | 64.545 | 71.057 |
| `sort_window` | 3.089 | 86.824 | **89.913** | 67.305 | 74.196 |
| `bloom_filter` | 3.350 | 85.120 | **88.470** | 67.551 | 70.033 |
| `hash_join` | 6.884 | 185.704 | **192.588** | 106.881 | 110.878 |
| `sieve` | 2.895 | 80.540 | **83.435** | 68.787 | 76.075 |
| `fib` | 2.486 | 73.515 | **76.001** | 59.062 | 61.178 |
| `collatz` | 2.771 | 78.635 | **81.406** | 61.049 | 64.699 |
| `matmul` | 3.457 | 85.517 | **88.974** | 70.031 | 89.538 |
| `json_parse` | 58.247 | 638.652 | **696.899** | 107.728 | 174.747 |
| `nbody` | 4.987 | 92.958 | **97.945** | 86.336 | 87.764 |

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
