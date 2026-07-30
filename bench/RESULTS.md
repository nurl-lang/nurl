# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T14:26:19Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `3c5fd67336c1a5dc525ca126a6489588df012759` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30551259484 |
| NURL | `v0.29.0-34-g3c5fd67` |
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
| _(floor: empty program)_ | _1.748_ | _1.922_ | _2.009_ | _24.692_ | _18.500_ |
| `lcg` | **39.512** | 39.667 | 39.643 | 1892.239 | 5205.823 |
| `packet_classifier` | 57.001 | 57.005 | **56.997** | 165.631 | 4532.402 |
| `ring_write` | **42.700** | 42.880 | 43.036 | 68.384 | 6471.742 |
| `histogram_bins` | **40.194** | 41.878 | 40.563 | 68.997 | 6083.812 |
| `prefix_scan` | **22.280** | 22.338 | 22.544 | 69.196 | 4433.148 |
| `binary_search` | 40.545 | **39.055** | 44.024 | 111.686 | 6181.042 |
| `sort_window` | 27.844 | 27.889 | **27.263** | 199.600 | 11433.165 |
| `bloom_filter` | **18.527** | 18.716 | 19.003 | 2871.546 | 7517.921 |
| `hash_join` | **29.021** | 31.112 | 30.711 | 3444.995 | 8297.224 |
| `sieve` | 21.066 | 18.617 | **18.585** | 67.370 | 3327.868 |
| `fib` | **25.795** | 30.479 | 28.650 | 134.446 | 1351.215 |
| `collatz` | 12.929 | **12.782** | 12.923 | 53.042 | 717.217 |
| `matmul` | 34.381 | **34.351** | 34.426 | 77.923 | 3112.206 |
| `json_parse` | **9.149** | 9.383 | 12.399 | 40.197 | 41.714 |
| `nbody` | 41.438 | 41.336 | **39.641** | 101.900 | 3159.490 |

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
| _(floor: empty program)_ | _3.315_ | _85.431_ | _**88.746**_ | _59.843_ | _63.510_ |
| `lcg` | 3.194 | 88.134 | **91.328** | 69.026 | 72.530 |
| `packet_classifier` | 3.527 | 91.391 | **94.918** | 73.266 | 78.250 |
| `ring_write` | 3.708 | 92.892 | **96.600** | 74.338 | 74.514 |
| `histogram_bins` | 3.799 | 97.245 | **101.044** | 76.923 | 78.548 |
| `prefix_scan` | 3.935 | 100.269 | **104.204** | 79.196 | 83.541 |
| `binary_search` | 4.403 | 98.759 | **103.162** | 76.779 | 84.225 |
| `sort_window` | 4.205 | 104.446 | **108.651** | 80.440 | 83.926 |
| `bloom_filter` | 4.612 | 101.734 | **106.346** | 81.211 | 77.726 |
| `hash_join` | 9.223 | 223.383 | **232.606** | 128.655 | 123.778 |
| `sieve` | 3.921 | 97.888 | **101.809** | 83.740 | 93.546 |
| `fib` | 3.352 | 90.699 | **94.051** | 72.970 | 72.833 |
| `collatz` | 3.815 | 96.988 | **100.803** | 72.177 | 73.139 |
| `matmul` | 4.778 | 102.196 | **106.974** | 85.438 | 98.090 |
| `json_parse` | 76.171 | 785.282 | **861.453** | 134.584 | 198.060 |
| `nbody` | 7.272 | 115.821 | **123.093** | 103.182 | 100.427 |

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
