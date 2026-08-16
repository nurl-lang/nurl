# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-16T07:02:39Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `c9f1dfb6d0c7defc7ef5b7497a5cf6f48a590824` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31932734063 |
| NURL | `v0.43.0-17-gc9f1dfb6` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.2 |
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
| _(floor: empty program)_ | _1.207_ | _1.253_ | _1.313_ | _15.991_ | _11.326_ |
| `lcg` | 30.054 | **30.034** | 30.140 | 1051.439 | 3181.737 |
| `packet_classifier` | **51.944** | 52.003 | 52.048 | 125.223 | 2628.437 |
| `ring_write` | 32.708 | 33.101 | **32.638** | 48.339 | 3828.499 |
| `histogram_bins` | 31.207 | **31.169** | 31.240 | 49.081 | 3541.129 |
| `prefix_scan` | **16.753** | 16.889 | 16.937 | 46.831 | 2759.509 |
| `binary_search` | **21.579** | 24.641 | 36.610 | 85.491 | 4105.245 |
| `sort_window` | **30.157** | 38.355 | 30.641 | 134.570 | 6804.960 |
| `bloom_filter` | **10.802** | 10.933 | 10.969 | 1848.605 | 4789.324 |
| `hash_join` | **18.055** | 19.734 | 20.034 | 2236.614 | 5200.199 |
| `sieve` | 33.809 | **33.490** | 33.651 | 69.481 | 2134.158 |
| `fib` | **17.377** | 20.497 | 19.376 | 82.429 | 665.334 |
| `collatz` | **11.310** | 11.559 | 12.297 | 45.855 | 418.585 |
| `matmul` | 15.086 | **14.656** | 15.215 | 53.575 | 1936.537 |
| `json_parse` | **5.537** | 5.970 | 7.037 | 22.892 | 24.497 |
| `nbody` | **16.487** | 23.693 | 21.796 | 60.321 | 1586.135 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc` emits LLVM IR, then `clang`
lowers and links it against `stdlib/runtime.o`. **NURL total** is the
number comparable to the C and Rust columns: a cold compile, measured
against a wiped cache exactly as C and Rust pay their full cost every
time. **NURL rebuild** is the same compile again with the ThinLTO
cache warm — `nurl.sh`'s default on Linux (docs/BUILDING.md → The
ThinLTO cache) — which is what every build after the first costs; C
and Rust have no default equivalent (`ccache`/`sccache` are opt-in
add-ons). The floor row is what each toolchain costs for a program
that does nothing — for NURL that is dominated by the LTO link every
NURL binary pays for, so subtract it to read the marginal cost of the
benchmark itself. Node and Python have no column here: they compile
at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | NURL rebuild | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.845_ | _52.681_ | _**54.526**_ | _33.726_ | _35.396_ | _46.006_ |
| `lcg` | 2.018 | 53.202 | **55.220** | 33.737 | 36.707 | 49.852 |
| `packet_classifier` | 2.206 | 57.385 | **59.591** | 35.459 | 41.293 | 50.296 |
| `ring_write` | 2.103 | 56.743 | **58.846** | 33.984 | 38.734 | 51.642 |
| `histogram_bins` | 2.212 | 67.598 | **69.810** | 34.832 | 39.023 | 53.722 |
| `prefix_scan` | 2.326 | 58.600 | **60.926** | 34.455 | 39.868 | 51.309 |
| `binary_search` | 2.324 | 61.175 | **63.499** | 35.043 | 39.054 | 54.424 |
| `sort_window` | 2.492 | 62.295 | **64.787** | 36.082 | 42.978 | 58.066 |
| `bloom_filter` | 2.975 | 66.596 | **69.571** | 39.956 | 51.333 | 61.416 |
| `hash_join` | 4.208 | 159.991 | **164.199** | 39.843 | 74.238 | 82.096 |
| `sieve` | 2.437 | 60.105 | **62.542** | 35.717 | 44.957 | 59.737 |
| `fib` | 2.214 | 57.886 | **60.100** | 37.575 | 39.754 | 50.900 |
| `collatz` | 2.279 | 60.342 | **62.621** | 36.914 | 41.079 | 53.182 |
| `matmul` | 2.457 | 59.157 | **61.614** | 34.969 | 44.918 | 67.133 |
| `json_parse` | 33.290 | 263.755 | **297.045** | 71.079 | 75.068 | 139.510 |
| `nbody` | 3.177 | 75.680 | **78.857** | 35.218 | 57.443 | 66.729 |

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
