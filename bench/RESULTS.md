# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-01T21:03:16Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373456 KiB |
| Commit | `7b02b1078f051087924d9dc1b9b2cc84e76df53c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30718140042 |
| NURL | `v0.30.0-37-g7b02b10` |
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
| _(floor: empty program)_ | _1.780_ | _1.799_ | _1.899_ | _24.892_ | _19.358_ |
| `lcg` | **39.676** | 39.720 | 39.840 | 1889.164 | 5202.522 |
| `packet_classifier` | 56.767 | **56.762** | 56.827 | 162.660 | 4560.152 |
| `ring_write` | 42.759 | **42.715** | 42.861 | 67.884 | 6228.845 |
| `histogram_bins` | **39.833** | 41.738 | 40.035 | 67.919 | 5933.130 |
| `prefix_scan` | **22.049** | 22.132 | 22.487 | 67.471 | 4586.443 |
| `binary_search` | 40.589 | **38.744** | 43.640 | 108.221 | 5937.615 |
| `sort_window` | 27.469 | 27.564 | **27.099** | 198.281 | 11602.616 |
| `bloom_filter` | **18.006** | 18.275 | 18.495 | 2803.898 | 7581.933 |
| `hash_join` | **28.268** | 30.561 | 30.240 | 3423.058 | 8367.015 |
| `sieve` | 19.114 | 18.635 | **18.331** | 66.562 | 3451.466 |
| `fib` | **25.274** | 30.044 | 28.351 | 130.818 | 1342.496 |
| `collatz` | 12.500 | **12.481** | 12.563 | 51.932 | 766.069 |
| `matmul` | 33.748 | 33.632 | **33.526** | 76.908 | 4146.217 |
| `json_parse` | **8.632** | 8.918 | 11.718 | 34.469 | 37.696 |
| `nbody` | 40.982 | 40.901 | **39.093** | 102.309 | 3035.667 |

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
| _(floor: empty program)_ | _2.972_ | _85.284_ | _**88.256**_ | _61.911_ | _67.116_ |
| `lcg` | 2.874 | 89.623 | **92.497** | 71.019 | 72.263 |
| `packet_classifier` | 2.907 | 88.216 | **91.123** | 67.204 | 67.656 |
| `ring_write` | 2.964 | 86.751 | **89.715** | 69.583 | 71.232 |
| `histogram_bins` | 3.028 | 90.614 | **93.642** | 72.890 | 74.212 |
| `prefix_scan` | 3.064 | 94.352 | **97.416** | 74.206 | 75.867 |
| `binary_search` | 3.271 | 94.465 | **97.736** | 71.676 | 75.640 |
| `sort_window` | 3.292 | 100.311 | **103.603** | 78.842 | 81.801 |
| `bloom_filter` | 3.390 | 96.905 | **100.295** | 79.251 | 77.152 |
| `hash_join` | 5.450 | 214.177 | **219.627** | 121.597 | 111.783 |
| `sieve` | 3.045 | 91.304 | **94.349** | 78.254 | 79.088 |
| `fib` | 2.758 | 82.516 | **85.274** | 65.161 | 66.851 |
| `collatz` | 2.956 | 86.347 | **89.303** | 69.919 | 71.285 |
| `matmul` | 3.198 | 95.213 | **98.411** | 80.578 | 92.425 |
| `json_parse` | 39.931 | 510.098 | **550.029** | 123.129 | 178.426 |
| `nbody` | 4.306 | 105.330 | **109.636** | 96.234 | 93.293 |

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
