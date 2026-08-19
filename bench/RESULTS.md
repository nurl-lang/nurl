# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-19T16:37:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373444 KiB |
| Commit | `54cf32eb90bc1fc93d7fad798b4282224a79414c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32276385885 |
| NURL | `v0.45.0-9-g54cf32eb` |
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
| _(floor: empty program)_ | _1.636_ | _1.720_ | _1.858_ | _22.536_ | _17.217_ |
| `lcg` | 39.313 | **39.311** | 39.348 | 2050.578 | 5111.798 |
| `packet_classifier` | **56.336** | 56.424 | 56.652 | 162.080 | 4297.809 |
| `ring_write` | **42.342** | 42.487 | 42.602 | 66.231 | 6434.740 |
| `histogram_bins` | **39.802** | 41.480 | 39.825 | 66.081 | 5967.589 |
| `prefix_scan` | **21.873** | 21.908 | 22.051 | 65.123 | 4486.498 |
| `binary_search` | **36.428** | 38.556 | 43.507 | 107.137 | 6080.028 |
| `sort_window` | **26.763** | 27.433 | 27.017 | 196.977 | 11490.887 |
| `bloom_filter` | **18.021** | 18.254 | 18.567 | 2867.059 | 7545.996 |
| `hash_join` | **26.980** | 30.127 | 29.951 | 3438.760 | 8515.297 |
| `sieve` | 20.369 | **19.912** | 20.001 | 66.804 | 3273.410 |
| `fib` | **25.374** | 30.111 | 28.354 | 132.762 | 1356.014 |
| `collatz` | 12.502 | **12.476** | 12.563 | 49.694 | 722.775 |
| `matmul` | 33.931 | **33.701** | 33.957 | 76.354 | 3228.774 |
| `json_parse` | 9.111 | **8.830** | 11.732 | 35.106 | 37.379 |
| `nbody` | **25.378** | 41.087 | 39.201 | 100.919 | 3142.494 |

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
| _(floor: empty program)_ | _2.894_ | _94.863_ | _**97.757**_ | _58.603_ | _57.168_ | _62.533_ |
| `lcg` | 3.026 | 92.851 | **95.877** | 57.674 | 66.091 | 69.187 |
| `packet_classifier` | 3.105 | 92.734 | **95.839** | 57.084 | 69.816 | 68.650 |
| `ring_write` | 3.214 | 94.786 | **98.000** | 58.175 | 69.381 | 69.564 |
| `histogram_bins` | 3.262 | 114.079 | **117.341** | 58.535 | 71.076 | 72.287 |
| `prefix_scan` | 3.327 | 98.815 | **102.142** | 58.642 | 73.170 | 72.379 |
| `binary_search` | 3.500 | 103.669 | **107.169** | 58.808 | 70.924 | 75.859 |
| `sort_window` | 3.508 | 104.190 | **107.698** | 58.914 | 75.091 | 78.928 |
| `bloom_filter` | 3.735 | 100.861 | **104.596** | 58.685 | 75.981 | 74.184 |
| `hash_join` | 6.226 | 254.202 | **260.428** | 61.014 | 122.404 | 109.683 |
| `sieve` | 3.344 | 96.506 | **99.850** | 58.435 | 78.293 | 80.217 |
| `fib` | 3.004 | 93.040 | **96.044** | 57.634 | 66.362 | 68.211 |
| `collatz` | 3.222 | 98.523 | **101.745** | 58.420 | 67.970 | 70.273 |
| `matmul` | 3.568 | 99.792 | **103.360** | 58.786 | 81.315 | 91.892 |
| `json_parse` | 52.445 | 431.449 | **483.894** | 109.917 | 124.231 | 181.209 |
| `nbody` | 4.925 | 124.712 | **129.637** | 59.789 | 96.891 | 93.903 |

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
