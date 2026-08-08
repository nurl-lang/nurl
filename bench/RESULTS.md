# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-08T04:17:01Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372444 KiB |
| Commit | `8a7dd0bbe85eff63c710dbfff72355d3138ffe54` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31238948211 |
| NURL | `v0.35.1-16-g8a7dd0bb` |
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
| _(floor: empty program)_ | _1.252_ | _1.273_ | _1.416_ | _17.987_ | _13.353_ |
| `lcg` | **35.722** | 35.822 | 35.902 | 1337.338 | 3897.003 |
| `packet_classifier` | **56.554** | 62.065 | 61.014 | 146.219 | 3302.662 |
| `ring_write` | 38.819 | **38.811** | 39.525 | 57.974 | 4514.890 |
| `histogram_bins` | 37.215 | 36.691 | **36.468** | 59.188 | 4336.595 |
| `prefix_scan` | **19.757** | 20.188 | 19.994 | 58.984 | 3237.365 |
| `binary_search` | 30.273 | **27.837** | 38.725 | 97.914 | 4730.342 |
| `sort_window` | 36.932 | 46.425 | **35.543** | 157.918 | 8228.179 |
| `bloom_filter` | 13.046 | **12.555** | 12.707 | 2134.159 | 5999.999 |
| `hash_join` | **21.580** | 23.457 | 24.252 | 2668.702 | 6279.604 |
| `sieve` | 34.190 | **33.625** | 33.631 | 74.969 | 2578.865 |
| `fib` | 26.278 | 27.437 | **22.861** | 99.760 | 797.453 |
| `collatz` | **13.303** | 13.322 | 13.576 | 52.145 | 497.648 |
| `matmul` | 18.313 | 18.003 | **17.805** | 63.706 | 2349.551 |
| `json_parse` | 31.347 | **6.837** | 8.475 | 26.517 | 29.387 |
| `nbody` | 29.400 | 28.557 | **28.129** | 69.252 | 2065.369 |

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
| _(floor: empty program)_ | _2.055_ | _58.930_ | _**60.985**_ | _39.677_ | _50.585_ |
| `lcg` | 2.038 | 61.183 | **63.221** | 44.884 | 56.893 |
| `packet_classifier` | 2.268 | 60.930 | **63.198** | 52.459 | 54.929 |
| `ring_write` | 2.390 | 63.344 | **65.734** | 45.194 | 57.426 |
| `histogram_bins` | 2.478 | 68.483 | **70.961** | 47.516 | 58.248 |
| `prefix_scan` | 2.351 | 67.083 | **69.434** | 51.119 | 60.245 |
| `binary_search` | 2.548 | 64.646 | **67.194** | 47.965 | 60.164 |
| `sort_window` | 2.586 | 70.101 | **72.687** | 49.403 | 62.860 |
| `bloom_filter` | 2.795 | 73.571 | **76.366** | 51.248 | 60.824 |
| `hash_join` | 4.427 | 161.793 | **166.220** | 88.515 | 93.554 |
| `sieve` | 2.252 | 67.715 | **69.967** | 52.955 | 64.048 |
| `fib` | 2.238 | 64.665 | **66.903** | 47.534 | 54.291 |
| `collatz` | 2.331 | 67.475 | **69.806** | 49.469 | 58.995 |
| `matmul` | 2.639 | 70.119 | **72.758** | 55.386 | 74.028 |
| `json_parse` | 34.287 | 411.746 | **446.033** | 89.784 | 159.493 |
| `nbody` | 3.342 | 84.207 | **87.549** | 68.668 | 75.708 |

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
