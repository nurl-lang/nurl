# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-28T17:06:52Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `2996a9ed2f2db1dd351461f897b0c849331c12b0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30381086145 |
| NURL | `v0.27.0-28-g2996a9e` |
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
| _(floor: empty program)_ | _1.242_ | _1.270_ | _1.357_ | _18.360_ | _13.396_ |
| `lcg` | **35.409** | 35.581 | 35.641 | 1321.964 | 3865.797 |
| `packet_classifier` | **56.518** | 62.800 | 62.209 | 147.088 | 3161.431 |
| `ring_write` | 38.953 | **38.527** | 38.920 | 58.144 | 4555.943 |
| `histogram_bins` | **36.302** | 36.474 | 36.563 | 59.121 | 4301.111 |
| `prefix_scan` | **19.910** | 20.422 | 20.420 | 58.905 | 3230.231 |
| `binary_search` | 30.245 | **28.215** | 38.972 | 102.428 | 4684.373 |
| `sort_window` | 38.371 | 46.388 | **35.806** | 158.447 | 8257.032 |
| `bloom_filter` | 12.890 | **12.838** | 12.949 | 2132.325 | 5771.991 |
| `hash_join` | **21.525** | 23.189 | 24.189 | 2709.381 | 6307.057 |
| `sieve` | 33.517 | 32.274 | **31.964** | 73.290 | 2460.745 |
| `fib` | 26.160 | 28.505 | **23.309** | 101.612 | 791.581 |
| `collatz` | **13.420** | 14.152 | 13.637 | 52.501 | 505.428 |
| `matmul` | 19.075 | **18.166** | 18.809 | 63.391 | 2245.139 |
| `json_parse` | **6.334** | 6.818 | 8.456 | 29.828 | 30.273 |
| `nbody` | 28.740 | 29.074 | **26.570** | 70.151 | 1895.675 |

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
| _(floor: empty program)_ | _2.107_ | _62.657_ | _**64.764**_ | _43.060_ | _50.971_ |
| `lcg` | 2.166 | 61.040 | **63.206** | 45.456 | 57.614 |
| `packet_classifier` | 2.248 | 62.659 | **64.907** | 66.833 | 54.808 |
| `ring_write` | 2.385 | 63.471 | **65.856** | 46.571 | 54.711 |
| `histogram_bins` | 2.463 | 67.386 | **69.849** | 48.314 | 59.015 |
| `prefix_scan` | 2.611 | 69.699 | **72.310** | 51.806 | 60.269 |
| `binary_search` | 2.791 | 66.421 | **69.212** | 51.674 | 65.993 |
| `sort_window` | 2.845 | 74.038 | **76.883** | 55.589 | 67.931 |
| `bloom_filter` | 3.072 | 74.841 | **77.913** | 59.702 | 66.924 |
| `hash_join` | 6.437 | 159.433 | **165.870** | 88.753 | 96.448 |
| `sieve` | 2.551 | 68.701 | **71.252** | 56.257 | 68.968 |
| `fib` | 2.236 | 62.869 | **65.105** | 50.223 | 58.025 |
| `collatz` | 2.531 | 71.424 | **73.955** | 49.038 | 59.225 |
| `matmul` | 3.398 | 74.190 | **77.588** | 61.063 | 81.068 |
| `json_parse` | 53.830 | 564.498 | **618.328** | 91.622 | 164.353 |
| `nbody` | 5.032 | 81.610 | **86.642** | 69.920 | 77.888 |

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
