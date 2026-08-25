# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-25T20:58:38Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `e3f141934fb48170e7edb238c94f1d4d4b7eb3b5` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32898034497 |
| NURL | `v0.52.0-2-ge3f14193` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |
| Node | v22.23.2 |
| Python | Python 3.12.3 |

| Setting | Value |
|---|---|
| NURL flags | `nurlc` → LLVM IR; `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` (ThinLTO backend at O3 — the standard `nurl.sh` release pipeline) |
| C flags | `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` — the identical pipeline, so neither column gets a backend the other lacks |
| Rust flags | `rustc -C opt-level=3` — rustc has no prelink/backend split; opt-level 3 is the `cargo build --release` default |
| Node / Python | `node` / `python3`, no flags |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.230_ | _1.198_ | _1.358_ | _20.076_ | _13.626_ |
| `lcg` | **34.168** | 34.171 | 34.262 | 1411.208 | 4353.669 |
| `packet_classifier` | 49.229 | **49.182** | 49.359 | 123.533 | 3893.007 |
| `ring_write` | 36.926 | **36.868** | 37.043 | 57.036 | 5056.693 |
| `histogram_bins` | **34.514** | 34.555 | 34.686 | 57.356 | 4915.006 |
| `prefix_scan` | 18.914 | **18.891** | 19.061 | 55.301 | 3772.863 |
| `binary_search` | **26.445** | 27.702 | 28.218 | 86.263 | 5474.983 |
| `sort_window` | **23.220** | 23.228 | 23.340 | 127.987 | 8582.644 |
| `bloom_filter` | 15.215 | **14.486** | 16.008 | 2119.827 | 6146.152 |
| `hash_join` | **21.370** | 22.124 | 23.312 | 2659.515 | 6466.028 |
| `sieve` | 15.769 | 15.551 | **15.543** | 56.002 | 2666.069 |
| `fib` | **21.537** | 25.647 | 21.740 | 110.465 | 1003.034 |
| `collatz` | 10.613 | **10.584** | 10.706 | 39.223 | 588.478 |
| `matmul` | 36.312 | **35.903** | 36.067 | 65.629 | 2693.024 |
| `json_parse` | **6.815** | 6.976 | 9.447 | 29.970 | 29.202 |
| `nbody` | 20.802 | 34.763 | **20.326** | 76.122 | 2509.093 |

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
| _(floor: empty program)_ | _2.347_ | _79.553_ | _**81.900**_ | _51.070_ | _70.617_ | _46.319_ |
| `lcg` | 2.443 | 81.562 | **84.005** | 50.525 | 77.267 | 51.902 |
| `packet_classifier` | 2.531 | 81.002 | **83.533** | 50.700 | 77.680 | 51.495 |
| `ring_write` | 2.640 | 81.937 | **84.577** | 51.012 | 78.461 | 53.115 |
| `histogram_bins` | 2.660 | 96.103 | **98.763** | 51.183 | 91.597 | 58.579 |
| `prefix_scan` | 2.689 | 84.660 | **87.349** | 51.403 | 83.328 | 55.664 |
| `binary_search` | 2.823 | 88.594 | **91.417** | 51.719 | 80.473 | 57.043 |
| `sort_window` | 2.877 | 90.055 | **92.932** | 51.469 | 87.635 | 60.714 |
| `bloom_filter` | 3.031 | 88.203 | **91.234** | 51.768 | 85.950 | 56.954 |
| `hash_join` | 5.038 | 198.353 | **203.391** | 53.430 | 170.062 | 94.031 |
| `sieve` | 2.712 | 85.294 | **88.006** | 51.240 | 86.082 | 59.887 |
| `fib` | 2.480 | 82.290 | **84.770** | 51.489 | 77.821 | 51.265 |
| `collatz` | 2.618 | 83.609 | **86.227** | 51.057 | 78.950 | 53.889 |
| `matmul` | 2.921 | 85.669 | **88.590** | 51.359 | 89.345 | 70.305 |
| `json_parse` | 40.030 | 324.516 | **364.546** | 90.247 | 128.694 | 135.134 |
| `nbody` | 3.934 | 105.450 | **109.384** | 52.935 | 105.191 | 77.115 |

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
