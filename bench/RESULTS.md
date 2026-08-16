# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-16T16:10:01Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `9598cd64f3f91d236b7ef76d67381f047631790e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31957590053 |
| NURL | `v0.44.1` |
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
| _(floor: empty program)_ | _1.725_ | _1.761_ | _1.989_ | _25.021_ | _18.523_ |
| `lcg` | 39.619 | **39.586** | 39.732 | 2063.407 | 5294.566 |
| `packet_classifier` | **56.617** | 56.799 | 56.960 | 163.535 | 4470.202 |
| `ring_write` | **42.619** | 42.820 | 42.998 | 68.743 | 6525.882 |
| `histogram_bins` | **40.045** | 41.839 | 40.338 | 68.665 | 6166.763 |
| `prefix_scan` | **22.160** | 22.251 | 22.400 | 67.410 | 4698.170 |
| `binary_search` | **36.724** | 38.736 | 43.790 | 108.484 | 6093.007 |
| `sort_window` | **27.053** | 27.753 | 27.311 | 198.073 | 11586.851 |
| `bloom_filter` | **18.296** | 18.503 | 18.820 | 2914.425 | 7712.882 |
| `hash_join` | **27.413** | 30.464 | 30.285 | 3464.229 | 8461.548 |
| `sieve` | 20.842 | **19.150** | 19.168 | 67.762 | 3174.431 |
| `fib` | **25.615** | 30.477 | 28.730 | 132.394 | 1372.573 |
| `collatz` | **12.689** | 12.767 | 12.947 | 51.823 | 711.957 |
| `matmul` | 34.181 | **34.088** | 34.269 | 77.478 | 3114.615 |
| `json_parse` | 9.399 | **9.150** | 12.249 | 37.580 | 39.824 |
| `nbody` | **25.627** | 41.179 | 39.477 | 103.598 | 3025.675 |

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
| _(floor: empty program)_ | _2.975_ | _96.488_ | _**99.463**_ | _62.176_ | _61.526_ | _64.994_ |
| `lcg` | 3.195 | 97.841 | **101.036** | 62.116 | 71.080 | 71.707 |
| `packet_classifier` | 3.236 | 98.092 | **101.328** | 61.751 | 71.725 | 71.065 |
| `ring_write` | 3.338 | 99.387 | **102.725** | 63.029 | 73.176 | 73.722 |
| `histogram_bins` | 3.422 | 121.123 | **124.545** | 63.237 | 74.739 | 76.845 |
| `prefix_scan` | 3.537 | 104.842 | **108.379** | 62.990 | 77.723 | 75.545 |
| `binary_search` | 3.603 | 109.394 | **112.997** | 62.946 | 74.738 | 78.189 |
| `sort_window` | 3.678 | 111.886 | **115.564** | 63.104 | 80.044 | 84.670 |
| `bloom_filter` | 3.894 | 107.448 | **111.342** | 62.541 | 80.346 | 78.929 |
| `hash_join` | 6.556 | 267.367 | **273.923** | 67.189 | 127.828 | 116.543 |
| `sieve` | 3.470 | 102.763 | **106.233** | 62.605 | 83.305 | 83.434 |
| `fib` | 3.212 | 98.760 | **101.972** | 62.320 | 70.951 | 71.048 |
| `collatz` | 3.313 | 100.677 | **103.990** | 62.088 | 73.434 | 72.857 |
| `matmul` | 3.708 | 107.307 | **111.015** | 63.205 | 85.477 | 96.952 |
| `json_parse` | 53.686 | 454.785 | **508.471** | 115.341 | 130.985 | 189.077 |
| `nbody` | 5.173 | 132.389 | **137.562** | 64.973 | 101.915 | 98.540 |

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
