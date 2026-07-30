# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T17:23:18Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `7e34908459337109a1a237e75814722f4f128946` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30565357501 |
| NURL | `v0.29.0-46-g7e34908` |
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
| _(floor: empty program)_ | _1.837_ | _1.880_ | _2.049_ | _23.838_ | _18.156_ |
| `lcg` | **44.284** | 44.430 | 44.669 | 1836.291 | 5319.773 |
| `packet_classifier` | **63.750** | 63.794 | 63.891 | 159.638 | 4746.223 |
| `ring_write` | **47.886** | 47.899 | 48.112 | 73.149 | 6629.839 |
| `histogram_bins` | **44.794** | 44.937 | 45.069 | 74.665 | 6490.140 |
| `prefix_scan` | **24.662** | 24.724 | 24.863 | 71.120 | 4739.422 |
| `binary_search` | **35.904** | 35.915 | 46.164 | 110.723 | 6260.491 |
| `sort_window` | 30.918 | 30.943 | **30.415** | 168.557 | 11736.918 |
| `bloom_filter` | **19.934** | 20.537 | 20.902 | 2804.501 | 8074.471 |
| `hash_join` | **29.323** | 30.977 | 31.270 | 3469.435 | 8286.581 |
| `sieve` | 20.439 | 20.378 | **20.318** | 70.590 | 3486.280 |
| `fib` | **28.123** | 33.419 | 29.465 | 142.435 | 1287.526 |
| `collatz` | 13.952 | **13.899** | 14.028 | 52.199 | 754.153 |
| `matmul` | 45.675 | 46.962 | **45.643** | 82.810 | 3391.046 |
| `json_parse` | **8.523** | 9.065 | 12.565 | 36.916 | 37.708 |
| `nbody` | 46.309 | 46.446 | **44.166** | 93.840 | 3263.987 |

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
| _(floor: empty program)_ | _3.345_ | _87.869_ | _**91.214**_ | _66.404_ | _79.026_ |
| `lcg` | 3.597 | 94.495 | **98.092** | 73.407 | 73.767 |
| `packet_classifier` | 3.665 | 94.524 | **98.189** | 72.930 | 73.932 |
| `ring_write` | 3.897 | 95.592 | **99.489** | 73.984 | 74.784 |
| `histogram_bins` | 4.014 | 98.232 | **102.246** | 76.265 | 77.623 |
| `prefix_scan` | 4.180 | 98.230 | **102.410** | 78.063 | 77.115 |
| `binary_search` | 4.400 | 96.418 | **100.818** | 74.993 | 79.847 |
| `sort_window` | 4.490 | 103.152 | **107.642** | 80.532 | 83.351 |
| `bloom_filter` | 4.814 | 101.859 | **106.673** | 80.593 | 79.677 |
| `hash_join` | 9.514 | 210.435 | **219.949** | 120.380 | 116.409 |
| `sieve` | 4.101 | 97.395 | **101.496** | 82.473 | 84.893 |
| `fib` | 3.552 | 90.822 | **94.374** | 71.584 | 71.767 |
| `collatz` | 3.942 | 95.069 | **99.011** | 72.943 | 75.149 |
| `matmul` | 4.795 | 101.398 | **106.193** | 84.324 | 97.197 |
| `json_parse` | 77.098 | 693.507 | **770.605** | 124.797 | 185.048 |
| `nbody` | 7.209 | 113.275 | **120.484** | 99.044 | 97.333 |

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
