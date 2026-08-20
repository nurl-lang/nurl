# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-20T14:05:04Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e4535b010e633955d28a4a14f02472146f261cd0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32377517330 |
| NURL | `v0.46.0-10-ge4535b01` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.2 |
| Python | Python 3.12.3 |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `clang -O2 -flto=thin` + ThinLTO backend O3, Rust `-C opt-level=3` |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.580_ | _1.559_ | _1.810_ | _25.285_ | _18.242_ |
| `lcg` | 44.227 | **44.124** | 44.370 | 1817.035 | 5286.906 |
| `packet_classifier` | 63.589 | **63.546** | 63.722 | 160.803 | 4483.926 |
| `ring_write` | **47.698** | 47.714 | 47.833 | 75.148 | 6521.791 |
| `histogram_bins` | 44.747 | **44.552** | 44.752 | 75.864 | 6335.550 |
| `prefix_scan` | 24.532 | **24.526** | 24.772 | 73.049 | 4887.665 |
| `binary_search` | **34.333** | 35.790 | 41.742 | 112.623 | 6495.148 |
| `sort_window` | 30.139 | **30.106** | 30.430 | 165.561 | 11477.365 |
| `bloom_filter` | 19.709 | **18.691** | 20.651 | 2691.624 | 8473.816 |
| `hash_join` | **27.751** | 28.666 | 30.203 | 3491.929 | 8220.276 |
| `sieve` | 20.723 | **19.984** | 20.369 | 70.410 | 3304.119 |
| `fib` | **27.893** | 33.106 | 29.280 | 142.744 | 1292.389 |
| `collatz` | 13.688 | **13.664** | 13.778 | 51.533 | 752.162 |
| `matmul` | **45.304** | 46.278 | 47.236 | 84.179 | 3707.431 |
| `json_parse` | **8.702** | 8.817 | 12.403 | 39.798 | 38.958 |
| `nbody` | 26.804 | 44.906 | **26.267** | 96.513 | 3273.930 |

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
| _(floor: empty program)_ | _3.038_ | _106.531_ | _**109.569**_ | _66.725_ | _90.589_ | _70.031_ |
| `lcg` | 3.168 | 107.832 | **111.000** | 65.681 | 110.842 | 76.283 |
| `packet_classifier` | 3.272 | 108.071 | **111.343** | 67.171 | 103.500 | 76.529 |
| `ring_write` | 3.371 | 108.646 | **112.017** | 66.900 | 104.113 | 78.043 |
| `histogram_bins` | 3.448 | 126.499 | **129.947** | 67.325 | 119.200 | 85.343 |
| `prefix_scan` | 3.462 | 112.130 | **115.592** | 67.946 | 110.273 | 82.743 |
| `binary_search` | 3.641 | 117.104 | **120.745** | 68.414 | 106.212 | 83.548 |
| `sort_window` | 3.782 | 124.151 | **127.933** | 68.526 | 117.148 | 89.528 |
| `bloom_filter` | 3.914 | 113.335 | **117.249** | 66.894 | 111.985 | 92.572 |
| `hash_join` | 6.476 | 260.769 | **267.245** | 70.761 | 221.313 | 134.517 |
| `sieve` | 3.487 | 110.041 | **113.528** | 66.475 | 112.501 | 87.370 |
| `fib` | 3.218 | 103.770 | **106.988** | 65.263 | 98.396 | 73.222 |
| `collatz` | 3.315 | 106.005 | **109.320** | 64.813 | 99.990 | 77.571 |
| `matmul` | 3.720 | 107.929 | **111.649** | 65.109 | 112.606 | 99.143 |
| `json_parse` | 52.042 | 422.559 | **474.601** | 117.318 | 168.786 | 190.188 |
| `nbody` | 5.047 | 134.376 | **139.423** | 67.025 | 134.562 | 112.490 |

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
