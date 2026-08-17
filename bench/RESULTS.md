# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-17T18:15:28Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `53dc4aafd417bd9c0019dfc6388abe108b97232e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32053670838 |
| NURL | `v0.44.2-18-g53dc4aaf` |
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
| _(floor: empty program)_ | _1.811_ | _1.949_ | _2.072_ | _23.384_ | _17.842_ |
| `lcg` | **44.314** | 44.382 | 44.471 | 1822.720 | 5408.115 |
| `packet_classifier` | **63.715** | 63.750 | 63.956 | 157.846 | 4572.420 |
| `ring_write` | **47.777** | 47.912 | 48.048 | 72.952 | 7004.006 |
| `histogram_bins` | **44.768** | 44.843 | 45.009 | 74.265 | 6209.089 |
| `prefix_scan` | **24.653** | 24.755 | 24.887 | 73.393 | 4774.857 |
| `binary_search` | **34.165** | 35.936 | 46.104 | 113.315 | 6527.299 |
| `sort_window` | **30.220** | 30.937 | 30.361 | 169.989 | 10892.777 |
| `bloom_filter` | **19.910** | 20.578 | 20.933 | 2712.566 | 7980.487 |
| `hash_join` | **27.731** | 30.928 | 31.393 | 3507.101 | 8123.467 |
| `sieve` | 20.825 | **20.364** | 20.405 | 70.333 | 3433.178 |
| `fib` | **28.098** | 33.485 | 29.539 | 143.212 | 1290.563 |
| `collatz` | **13.881** | 13.951 | 14.002 | 52.252 | 757.239 |
| `matmul` | **45.374** | 45.701 | 45.929 | 84.662 | 3580.432 |
| `json_parse` | **8.942** | 9.150 | 12.340 | 39.338 | 39.529 |
| `nbody` | **27.048** | 46.569 | 44.239 | 98.900 | 3186.927 |

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
| _(floor: empty program)_ | _3.158_ | _97.250_ | _**100.408**_ | _64.095_ | _64.437_ | _65.230_ |
| `lcg` | 3.319 | 99.195 | **102.514** | 63.726 | 72.778 | 73.404 |
| `packet_classifier` | 3.469 | 101.383 | **104.852** | 65.242 | 73.421 | 73.311 |
| `ring_write` | 3.579 | 102.824 | **106.403** | 64.093 | 75.055 | 73.917 |
| `histogram_bins` | 3.662 | 122.102 | **125.764** | 64.490 | 76.580 | 77.963 |
| `prefix_scan` | 3.701 | 111.855 | **115.556** | 66.560 | 80.783 | 77.189 |
| `binary_search` | 3.800 | 111.835 | **115.635** | 65.123 | 77.123 | 78.999 |
| `sort_window` | 3.875 | 113.217 | **117.092** | 64.739 | 82.224 | 83.176 |
| `bloom_filter` | 4.085 | 109.778 | **113.863** | 64.833 | 82.734 | 79.515 |
| `hash_join` | 6.589 | 251.875 | **258.464** | 67.259 | 123.446 | 116.555 |
| `sieve` | 3.708 | 107.435 | **111.143** | 65.383 | 85.314 | 85.602 |
| `fib` | 3.367 | 100.690 | **104.057** | 64.242 | 73.671 | 73.163 |
| `collatz` | 3.591 | 105.571 | **109.162** | 66.125 | 76.339 | 75.420 |
| `matmul` | 3.960 | 110.340 | **114.300** | 66.164 | 87.402 | 98.730 |
| `json_parse` | 52.084 | 423.240 | **475.324** | 116.236 | 128.441 | 188.550 |
| `nbody` | 5.300 | 137.585 | **142.885** | 68.862 | 104.887 | 100.707 |

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
