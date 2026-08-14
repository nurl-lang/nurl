# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-14T13:40:15Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `27dba6105c7be96373dd27b758f5877f2e60aaab` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31805440450 |
| NURL | `v0.42.0-6-g27dba610` |
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
| _(floor: empty program)_ | _1.660_ | _1.737_ | _1.858_ | _23.319_ | _17.666_ |
| `lcg` | **39.227** | 39.483 | 39.450 | 2058.175 | 5098.541 |
| `packet_classifier` | **56.485** | 56.495 | 56.610 | 162.415 | 4374.318 |
| `ring_write` | **42.424** | 42.755 | 42.626 | 67.301 | 6318.606 |
| `histogram_bins` | **39.670** | 41.369 | 39.945 | 67.792 | 6194.272 |
| `prefix_scan` | **21.922** | 21.928 | 22.064 | 65.861 | 4842.796 |
| `binary_search` | **36.355** | 38.510 | 43.460 | 106.671 | 6188.650 |
| `sort_window` | 26.905 | 27.554 | **26.904** | 199.616 | 11608.870 |
| `bloom_filter` | **18.058** | 18.222 | 18.577 | 2836.391 | 7523.968 |
| `hash_join` | **27.491** | 30.395 | 30.250 | 3425.764 | 8427.907 |
| `sieve` | 20.488 | 20.637 | **20.384** | 66.935 | 3441.873 |
| `fib` | **25.336** | 30.166 | 28.376 | 132.243 | 1364.593 |
| `collatz` | **12.428** | 12.491 | 12.553 | 48.578 | 721.193 |
| `matmul` | **33.663** | 33.669 | 34.010 | 76.173 | 3074.477 |
| `json_parse` | 9.032 | **8.874** | 11.827 | 36.248 | 38.182 |
| `nbody` | **25.261** | 40.869 | 39.195 | 100.710 | 3048.524 |

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
| _(floor: empty program)_ | _2.815_ | _91.428_ | _**94.243**_ | _60.224_ | _58.631_ | _61.285_ |
| `lcg` | 2.898 | 91.861 | **94.759** | 58.115 | 66.566 | 67.856 |
| `packet_classifier` | 3.109 | 94.379 | **97.488** | 60.388 | 69.758 | 69.425 |
| `ring_write` | 3.112 | 94.385 | **97.497** | 59.227 | 70.385 | 71.971 |
| `histogram_bins` | 3.185 | 115.149 | **118.334** | 59.060 | 71.476 | 73.244 |
| `prefix_scan` | 3.150 | 99.406 | **102.556** | 59.655 | 72.878 | 72.952 |
| `binary_search` | 3.336 | 104.210 | **107.546** | 59.243 | 69.568 | 75.406 |
| `sort_window` | 3.416 | 107.595 | **111.011** | 59.460 | 76.336 | 79.930 |
| `bloom_filter` | 3.607 | 104.286 | **107.893** | 59.372 | 76.740 | 74.985 |
| `hash_join` | 6.036 | 259.962 | **265.998** | 63.679 | 121.555 | 113.033 |
| `sieve` | 3.185 | 98.312 | **101.497** | 59.431 | 80.171 | 87.098 |
| `fib` | 2.948 | 93.635 | **96.583** | 60.364 | 67.172 | 68.202 |
| `collatz` | 3.140 | 96.587 | **99.727** | 59.423 | 69.262 | 70.704 |
| `matmul` | 3.416 | 100.781 | **104.197** | 59.528 | 81.767 | 92.581 |
| `json_parse` | 47.916 | 432.837 | **480.753** | 105.920 | 123.397 | 183.799 |
| `nbody` | 4.651 | 126.562 | **131.213** | 61.024 | 97.165 | 94.627 |

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
