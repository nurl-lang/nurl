# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T12:07:58Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373460 KiB |
| Commit | `e4231239deb432f55c4b34c59cb4ee8a6b9ea0c2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30540990230 |
| NURL | `v0.29.0-19-ge423123` |
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
| _(floor: empty program)_ | _1.395_ | _1.463_ | _1.573_ | _19.462_ | _14.156_ |
| `lcg` | **34.331** | 34.455 | 34.614 | 1432.474 | 4199.063 |
| `packet_classifier` | **49.478** | 49.480 | 49.679 | 123.206 | 4022.337 |
| `ring_write` | **37.147** | 37.270 | 37.317 | 57.687 | 5191.461 |
| `histogram_bins` | **34.778** | 34.886 | 34.940 | 58.112 | 4911.773 |
| `prefix_scan` | **19.130** | 19.132 | 19.310 | 57.208 | 3734.093 |
| `binary_search` | 27.928 | **27.883** | 35.951 | 88.217 | 5065.230 |
| `sort_window` | 24.002 | 24.083 | **23.663** | 130.300 | 8665.933 |
| `bloom_filter` | **15.474** | 15.984 | 16.211 | 2131.078 | 6016.862 |
| `hash_join` | **22.802** | 24.074 | 24.229 | 2647.885 | 6611.288 |
| `sieve` | 16.066 | **15.876** | 16.083 | 55.765 | 2834.242 |
| `fib` | **21.751** | 25.949 | 22.901 | 111.959 | 1008.274 |
| `collatz` | **10.818** | 10.867 | 10.898 | 40.536 | 583.182 |
| `matmul` | 35.863 | 36.510 | **35.809** | 64.778 | 2824.556 |
| `json_parse` | **6.485** | 7.148 | 9.519 | 29.412 | 29.361 |
| `nbody` | 35.948 | 36.036 | **34.367** | 74.842 | 2504.526 |

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
| _(floor: empty program)_ | _2.598_ | _70.535_ | _**73.133**_ | _60.579_ | _53.485_ |
| `lcg` | 2.736 | 75.753 | **78.489** | 59.682 | 59.760 |
| `packet_classifier` | 2.893 | 78.764 | **81.657** | 61.010 | 60.172 |
| `ring_write` | 3.022 | 79.865 | **82.887** | 61.688 | 61.483 |
| `histogram_bins` | 3.197 | 81.073 | **84.270** | 63.352 | 63.801 |
| `prefix_scan` | 3.246 | 82.778 | **86.024** | 63.986 | 64.358 |
| `binary_search` | 3.461 | 81.773 | **85.234** | 63.387 | 64.537 |
| `sort_window` | 3.501 | 87.382 | **90.883** | 71.629 | 68.861 |
| `bloom_filter` | 3.795 | 83.696 | **87.491** | 66.975 | 65.266 |
| `hash_join` | 7.333 | 164.960 | **172.293** | 100.191 | 92.287 |
| `sieve` | 3.203 | 80.665 | **83.868** | 67.973 | 68.506 |
| `fib` | 2.779 | 73.997 | **76.776** | 58.281 | 58.860 |
| `collatz` | 3.123 | 78.188 | **81.311** | 60.525 | 61.057 |
| `matmul` | 3.823 | 83.453 | **87.276** | 69.603 | 79.797 |
| `json_parse` | 59.299 | 540.468 | **599.767** | 99.415 | 147.879 |
| `nbody` | 5.677 | 92.506 | **98.183** | 80.717 | 79.705 |

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
