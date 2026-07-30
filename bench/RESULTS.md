# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T11:09:52Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373456 KiB |
| Commit | `758848bbb6d0f427172740b29ceedac90f23b606` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30537158465 |
| NURL | `v0.29.0-12-g758848b` |
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
| _(floor: empty program)_ | _1.845_ | _1.907_ | _2.039_ | _25.060_ | _18.385_ |
| `lcg` | **44.514** | 44.582 | 44.689 | 1859.677 | 5304.054 |
| `packet_classifier` | 63.978 | **63.977** | 64.147 | 160.179 | 4772.311 |
| `ring_write` | **47.972** | 48.120 | 48.266 | 75.650 | 8192.282 |
| `histogram_bins` | 45.058 | **45.029** | 45.166 | 76.551 | 6687.620 |
| `prefix_scan` | **24.846** | 24.928 | 25.146 | 74.354 | 4831.078 |
| `binary_search` | **36.074** | 36.209 | 46.359 | 115.074 | 6553.277 |
| `sort_window` | 31.065 | 31.344 | **30.678** | 173.286 | 11657.254 |
| `bloom_filter` | **20.080** | 20.625 | 20.998 | 2770.825 | 7741.859 |
| `hash_join` | **29.559** | 31.175 | 31.631 | 3391.997 | 8289.240 |
| `sieve` | 20.963 | **20.765** | 20.797 | 73.190 | 3368.280 |
| `fib` | **28.401** | 33.704 | 29.774 | 144.053 | 1314.278 |
| `collatz` | **14.031** | 14.057 | 14.206 | 54.490 | 756.446 |
| `matmul` | **45.091** | 45.856 | 45.692 | 84.630 | 3324.292 |
| `json_parse` | **8.466** | 9.170 | 12.594 | 39.987 | 39.193 |
| `nbody` | 46.429 | 46.597 | **44.344** | 99.612 | 3376.461 |

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
| _(floor: empty program)_ | _3.451_ | _94.818_ | _**98.269**_ | _70.052_ | _69.027_ |
| `lcg` | 3.607 | 100.058 | **103.665** | 77.718 | 78.307 |
| `packet_classifier` | 3.692 | 102.458 | **106.150** | 79.761 | 79.021 |
| `ring_write` | 4.018 | 103.221 | **107.239** | 80.008 | 80.765 |
| `histogram_bins` | 4.092 | 107.782 | **111.874** | 83.958 | 85.966 |
| `prefix_scan` | 4.134 | 109.128 | **113.262** | 84.324 | 81.324 |
| `binary_search` | 4.452 | 106.384 | **110.836** | 81.766 | 85.573 |
| `sort_window` | 4.591 | 114.707 | **119.298** | 88.329 | 89.077 |
| `bloom_filter` | 4.896 | 110.240 | **115.136** | 87.401 | 87.369 |
| `hash_join` | 9.744 | 220.193 | **229.937** | 129.908 | 123.572 |
| `sieve` | 4.121 | 106.499 | **110.620** | 88.504 | 90.367 |
| `fib` | 3.569 | 98.850 | **102.419** | 80.033 | 76.943 |
| `collatz` | 4.036 | 105.099 | **109.135** | 80.721 | 80.591 |
| `matmul` | 4.900 | 110.507 | **115.407** | 91.988 | 104.319 |
| `json_parse` | 79.134 | 708.296 | **787.430** | 130.300 | 196.768 |
| `nbody` | 7.485 | 121.316 | **128.801** | 105.587 | 103.930 |

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
