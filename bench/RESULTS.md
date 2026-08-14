# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-14T09:07:17Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377684 KiB |
| Commit | `ba36a73042e9c3e2b2a0ed0434535b84e776ad74` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31786439522 |
| NURL | `v0.42.0` |
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
| _(floor: empty program)_ | _1.645_ | _1.706_ | _1.842_ | _24.940_ | _17.666_ |
| `lcg` | **39.411** | 39.468 | 39.613 | 2054.182 | 5078.189 |
| `packet_classifier` | **56.499** | 56.551 | 56.777 | 161.381 | 4435.837 |
| `ring_write` | **42.478** | 42.675 | 42.721 | 67.180 | 6261.524 |
| `histogram_bins` | **39.770** | 41.578 | 39.925 | 66.245 | 5979.777 |
| `prefix_scan` | **21.799** | 21.933 | 22.034 | 63.948 | 4489.775 |
| `binary_search` | **36.525** | 38.631 | 43.572 | 106.656 | 5946.491 |
| `sort_window` | **26.833** | 27.452 | 26.875 | 197.990 | 11249.431 |
| `bloom_filter` | **18.044** | 18.252 | 18.573 | 2872.502 | 7844.877 |
| `hash_join` | **27.155** | 30.175 | 30.067 | 3409.804 | 8102.557 |
| `sieve` | 21.146 | **18.212** | 20.638 | 66.228 | 3322.858 |
| `fib` | **25.410** | 30.272 | 28.556 | 131.405 | 1355.268 |
| `collatz` | 12.467 | **12.446** | 12.555 | 50.314 | 717.018 |
| `matmul` | 33.719 | **33.642** | 33.703 | 75.674 | 3167.624 |
| `json_parse` | 9.099 | **8.857** | 11.724 | 35.264 | 37.352 |
| `nbody` | **25.420** | 40.987 | 39.066 | 98.869 | 3055.187 |

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
| _(floor: empty program)_ | _2.768_ | _91.712_ | _**94.480**_ | _59.080_ | _58.081_ | _61.120_ |
| `lcg` | 2.879 | 92.964 | **95.843** | 59.280 | 68.026 | 69.080 |
| `packet_classifier` | 2.938 | 91.493 | **94.431** | 57.302 | 68.008 | 68.005 |
| `ring_write` | 3.027 | 94.106 | **97.133** | 59.324 | 65.843 | 69.213 |
| `histogram_bins` | 3.110 | 113.655 | **116.765** | 58.009 | 70.172 | 70.704 |
| `prefix_scan` | 3.150 | 98.728 | **101.878** | 58.682 | 72.791 | 70.233 |
| `binary_search` | 3.265 | 102.066 | **105.331** | 57.872 | 71.303 | 73.986 |
| `sort_window` | 3.326 | 105.881 | **109.207** | 58.981 | 75.606 | 80.392 |
| `bloom_filter` | 3.544 | 101.951 | **105.495** | 59.180 | 76.588 | 74.270 |
| `hash_join` | 5.848 | 255.714 | **261.562** | 61.023 | 119.391 | 110.222 |
| `sieve` | 3.171 | 97.231 | **100.402** | 58.913 | 78.986 | 79.439 |
| `fib` | 2.971 | 94.075 | **97.046** | 59.747 | 67.303 | 65.722 |
| `collatz` | 3.038 | 95.055 | **98.093** | 58.478 | 67.732 | 69.281 |
| `matmul` | 3.356 | 99.696 | **103.052** | 58.294 | 79.980 | 91.270 |
| `json_parse` | 47.203 | 430.471 | **477.674** | 105.288 | 123.062 | 177.573 |
| `nbody` | 4.594 | 123.859 | **128.453** | 59.573 | 95.477 | 91.347 |

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
