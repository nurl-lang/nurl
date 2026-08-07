# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-07T03:05:12Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `306a065edd0b4edc32ffb36892d5395cfe1d9141` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31143000130 |
| NURL | `v0.33.0-79-g306a065e` |
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
| _(floor: empty program)_ | _1.397_ | _1.452_ | _1.559_ | _23.099_ | _15.885_ |
| `lcg` | 41.449 | **41.401** | 41.618 | 1569.173 | 4373.601 |
| `packet_classifier` | **65.903** | 72.370 | 71.090 | 172.399 | 3625.085 |
| `ring_write` | **45.416** | 45.584 | 45.806 | 67.702 | 5226.819 |
| `histogram_bins` | 42.332 | **42.302** | 42.365 | 70.970 | 5058.781 |
| `prefix_scan` | **22.526** | 22.999 | 23.112 | 67.848 | 4009.185 |
| `binary_search` | 34.959 | **32.719** | 45.393 | 113.853 | 5553.130 |
| `sort_window` | 42.581 | 52.810 | **41.723** | 184.542 | 9390.818 |
| `bloom_filter` | **14.671** | 14.708 | 14.796 | 2431.041 | 7021.404 |
| `hash_join` | **25.171** | 27.192 | 27.740 | 3066.135 | 7322.873 |
| `sieve` | 37.504 | **36.604** | 37.380 | 85.439 | 2755.981 |
| `fib` | 29.527 | 30.903 | **26.582** | 114.983 | 913.153 |
| `collatz` | **15.555** | 15.680 | 16.363 | 61.314 | 577.826 |
| `matmul` | **21.015** | 21.129 | 21.297 | 76.729 | 2801.738 |
| `json_parse` | **7.488** | 7.903 | 9.867 | 32.301 | 34.169 |
| `nbody` | 33.353 | 33.436 | **30.793** | 83.360 | 2164.865 |

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
| _(floor: empty program)_ | _2.354_ | _74.526_ | _**76.880**_ | _51.614_ | _58.758_ |
| `lcg` | 2.492 | 76.376 | **78.868** | 57.493 | 67.821 |
| `packet_classifier` | 2.569 | 77.729 | **80.298** | 59.677 | 65.515 |
| `ring_write` | 2.725 | 86.151 | **88.876** | 61.198 | 83.678 |
| `histogram_bins` | 2.847 | 83.465 | **86.312** | 62.712 | 70.640 |
| `prefix_scan` | 2.817 | 83.105 | **85.922** | 66.306 | 70.911 |
| `binary_search` | 2.925 | 82.130 | **85.055** | 61.383 | 72.631 |
| `sort_window` | 3.000 | 90.756 | **93.756** | 69.074 | 79.809 |
| `bloom_filter` | 3.121 | 87.482 | **90.603** | 66.789 | 73.895 |
| `hash_join` | 5.057 | 181.944 | **187.001** | 104.945 | 108.563 |
| `sieve` | 2.798 | 84.742 | **87.540** | 71.014 | 78.234 |
| `fib` | 2.591 | 76.730 | **79.321** | 58.861 | 65.833 |
| `collatz` | 2.721 | 78.656 | **81.377** | 60.995 | 68.629 |
| `matmul` | 3.009 | 88.066 | **91.075** | 71.951 | 92.746 |
| `json_parse` | 39.237 | 459.343 | **498.580** | 109.669 | 184.762 |
| `nbody` | 3.903 | 97.219 | **101.122** | 86.124 | 91.921 |

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
