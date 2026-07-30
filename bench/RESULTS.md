# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T17:59:10Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `fe90fb6ea6ad0fe4bc97e8b5619b0a6d94c5d8e4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30568001653 |
| NURL | `v0.29.0-52-gfe90fb6` |
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
| _(floor: empty program)_ | _1.838_ | _1.861_ | _2.034_ | _26.843_ | _18.251_ |
| `lcg` | 44.459 | **44.457** | 44.754 | 1842.204 | 5352.806 |
| `packet_classifier` | **63.815** | 63.925 | 64.070 | 161.396 | 4680.905 |
| `ring_write` | 48.068 | **48.031** | 48.172 | 74.280 | 6664.979 |
| `histogram_bins` | 44.976 | **44.962** | 45.141 | 77.858 | 6213.071 |
| `prefix_scan` | **24.844** | 25.041 | 25.245 | 74.519 | 4760.939 |
| `binary_search` | **35.984** | 35.993 | 46.442 | 113.587 | 6614.281 |
| `sort_window` | 31.237 | 31.134 | **30.689** | 171.957 | 11179.107 |
| `bloom_filter` | **19.959** | 20.572 | 21.114 | 2726.378 | 7627.469 |
| `hash_join` | **29.498** | 31.104 | 31.431 | 3438.737 | 8084.195 |
| `sieve` | 21.286 | **21.269** | 21.433 | 76.371 | 3421.316 |
| `fib` | **28.487** | 33.763 | 29.695 | 144.524 | 1296.741 |
| `collatz` | 14.216 | **14.201** | 14.400 | 53.874 | 755.807 |
| `matmul` | 48.222 | **46.237** | 46.337 | 85.967 | 3357.328 |
| `json_parse` | **8.532** | 9.253 | 12.649 | 40.830 | 39.952 |
| `nbody` | 46.592 | 46.725 | **44.477** | 99.121 | 3226.131 |

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
| _(floor: empty program)_ | _3.356_ | _93.753_ | _**97.109**_ | _68.982_ | _68.408_ |
| `lcg` | 3.586 | 97.207 | **100.793** | 74.874 | 76.132 |
| `packet_classifier` | 3.879 | 101.101 | **104.980** | 79.491 | 76.981 |
| `ring_write` | 3.996 | 102.381 | **106.377** | 79.413 | 77.736 |
| `histogram_bins` | 4.062 | 105.265 | **109.327** | 79.376 | 79.746 |
| `prefix_scan` | 4.287 | 107.758 | **112.045** | 84.768 | 82.799 |
| `binary_search` | 4.513 | 106.169 | **110.682** | 80.822 | 89.462 |
| `sort_window` | 4.629 | 111.037 | **115.666** | 85.682 | 87.419 |
| `bloom_filter` | 4.883 | 108.677 | **113.560** | 86.115 | 85.626 |
| `hash_join` | 9.855 | 216.731 | **226.586** | 128.236 | 120.531 |
| `sieve` | 4.217 | 107.380 | **111.597** | 89.450 | 89.626 |
| `fib` | 3.574 | 96.705 | **100.279** | 76.557 | 78.918 |
| `collatz` | 4.118 | 104.903 | **109.021** | 79.776 | 87.666 |
| `matmul` | 5.218 | 114.587 | **119.805** | 93.288 | 105.832 |
| `json_parse` | 79.673 | 728.577 | **808.250** | 130.651 | 227.002 |
| `nbody` | 7.445 | 119.963 | **127.408** | 105.215 | 103.464 |

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
