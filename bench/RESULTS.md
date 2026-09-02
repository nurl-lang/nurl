# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-02T19:14:05Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `a50e7ddc877bc1fa31d104a95f177b4158354823` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33671634868 |
| NURL | `v0.58.0-16-ga50e7ddc` |
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
| _(floor: empty program)_ | _1.122_ | _1.087_ | _1.276_ | _15.597_ | _11.116_ |
| `lcg` | 28.872 | **27.813** | 27.993 | 1057.235 | 2862.249 |
| `packet_classifier` | 40.070 | **39.935** | 40.087 | 122.580 | 2507.961 |
| `ring_write` | 27.989 | **27.833** | 28.747 | 46.242 | 3571.780 |
| `histogram_bins` | 27.946 | **27.811** | 27.923 | 46.975 | 3257.164 |
| `prefix_scan` | **15.333** | 15.353 | 15.402 | 45.289 | 2465.615 |
| `binary_search` | **14.522** | 14.614 | 14.768 | 66.804 | 3685.702 |
| `sort_window` | **19.450** | 19.871 | 19.594 | 128.411 | 6035.931 |
| `bloom_filter` | 8.433 | **8.423** | 8.605 | 1548.624 | 4151.317 |
| `hash_join` | **15.278** | 16.085 | 17.208 | 1862.778 | 4260.440 |
| `sieve` | 11.324 | **11.106** | 11.244 | 41.211 | 1696.114 |
| `fib` | 18.561 | **18.345** | 18.613 | 73.025 | 693.189 |
| `collatz` | 9.265 | **8.909** | 8.999 | 33.320 | 440.849 |
| `matmul` | 20.167 | 19.740 | **19.697** | 49.661 | 1640.412 |
| `json_parse` | **4.841** | 4.920 | 6.598 | 21.554 | 21.945 |
| `nbody` | 15.977 | 23.659 | **15.664** | 55.093 | 1450.914 |

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
| _(floor: empty program)_ | _2.081_ | _71.157_ | _**73.238**_ | _43.112_ | _61.479_ | _47.677_ |
| `lcg` | 2.120 | 75.987 | **78.107** | 43.036 | 63.816 | 54.168 |
| `packet_classifier` | 2.234 | 78.612 | **80.846** | 43.817 | 67.722 | 53.670 |
| `ring_write` | 2.234 | 76.340 | **78.574** | 42.205 | 68.065 | 56.093 |
| `histogram_bins` | 2.339 | 83.237 | **85.576** | 43.265 | 75.993 | 59.633 |
| `prefix_scan` | 2.377 | 79.507 | **81.884** | 44.167 | 71.327 | 55.262 |
| `binary_search` | 2.377 | 75.238 | **77.615** | 42.148 | 66.850 | 60.963 |
| `sort_window` | 2.456 | 79.624 | **82.080** | 43.426 | 73.096 | 62.225 |
| `bloom_filter` | 2.577 | 78.333 | **80.910** | 42.948 | 71.840 | 58.050 |
| `hash_join` | 3.949 | 163.501 | **167.450** | 44.710 | 135.312 | 88.603 |
| `sieve` | 2.329 | 76.599 | **78.928** | 42.579 | 71.798 | 60.701 |
| `fib` | 2.210 | 77.722 | **79.932** | 42.185 | 66.773 | 54.085 |
| `collatz` | 2.249 | 75.968 | **78.217** | 42.330 | 67.476 | 55.450 |
| `matmul` | 2.458 | 77.923 | **80.381** | 43.519 | 74.825 | 72.608 |
| `json_parse` | 30.751 | 273.090 | **303.841** | 71.995 | 105.789 | 126.454 |
| `nbody` | 3.132 | 87.272 | **90.404** | 43.184 | 85.696 | 75.088 |

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
