# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-15T04:48:35Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `28764a0b1f8492d3019064e55f3aaf6bf2414ab6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31865140377 |
| NURL | `v0.42.0-27-g28764a0b` |
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
| _(floor: empty program)_ | _1.670_ | _1.742_ | _1.964_ | _23.567_ | _18.502_ |
| `lcg` | **39.560** | 39.726 | 39.914 | 2060.094 | 5372.870 |
| `packet_classifier` | **56.676** | 56.856 | 56.848 | 163.663 | 4416.002 |
| `ring_write` | 42.768 | **42.672** | 42.841 | 68.491 | 6377.993 |
| `histogram_bins` | **39.968** | 41.727 | 40.132 | 67.709 | 6081.898 |
| `prefix_scan` | **22.194** | 22.227 | 22.735 | 66.310 | 4481.527 |
| `binary_search` | **36.391** | 38.804 | 43.693 | 106.169 | 6180.116 |
| `sort_window` | 27.015 | 27.877 | **26.985** | 196.173 | 12502.169 |
| `bloom_filter` | **18.105** | 18.451 | 18.801 | 2870.282 | 7263.452 |
| `hash_join` | **27.296** | 30.340 | 30.121 | 3412.552 | 8374.579 |
| `sieve` | 18.915 | **18.438** | 18.664 | 65.433 | 3331.084 |
| `fib` | **25.686** | 30.532 | 28.786 | 132.863 | 1362.423 |
| `collatz` | 12.594 | **12.573** | 12.697 | 48.899 | 716.434 |
| `matmul` | 34.313 | **34.289** | 34.370 | 78.267 | 3428.287 |
| `json_parse` | 9.077 | **8.840** | 11.776 | 36.219 | 38.606 |
| `nbody` | **25.363** | 40.932 | 39.406 | 99.774 | 3131.899 |

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
| _(floor: empty program)_ | _3.713_ | _89.935_ | _**93.648**_ | _59.056_ | _56.885_ | _63.462_ |
| `lcg` | 3.036 | 95.233 | **98.269** | 60.394 | 68.898 | 70.553 |
| `packet_classifier` | 3.299 | 95.906 | **99.205** | 61.588 | 69.325 | 70.373 |
| `ring_write` | 3.214 | 97.598 | **100.812** | 60.811 | 71.410 | 72.749 |
| `histogram_bins` | 3.137 | 113.181 | **116.318** | 58.381 | 72.061 | 71.628 |
| `prefix_scan` | 3.419 | 101.207 | **104.626** | 60.525 | 73.328 | 73.813 |
| `binary_search` | 3.515 | 106.130 | **109.645** | 60.894 | 71.869 | 76.646 |
| `sort_window` | 3.422 | 109.504 | **112.926** | 61.120 | 79.207 | 86.417 |
| `bloom_filter` | 3.613 | 103.997 | **107.610** | 60.233 | 78.325 | 88.530 |
| `hash_join` | 6.086 | 258.643 | **264.729** | 63.731 | 123.084 | 112.531 |
| `sieve` | 3.227 | 96.403 | **99.630** | 59.683 | 77.678 | 81.476 |
| `fib` | 3.089 | 96.764 | **99.853** | 60.993 | 69.683 | 67.861 |
| `collatz` | 3.327 | 100.388 | **103.715** | 62.928 | 71.722 | 72.389 |
| `matmul` | 3.486 | 101.430 | **104.916** | 60.392 | 82.246 | 94.319 |
| `json_parse` | 48.539 | 427.124 | **475.663** | 105.294 | 121.585 | 175.881 |
| `nbody` | 5.431 | 125.433 | **130.864** | 61.582 | 95.669 | 92.319 |

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
