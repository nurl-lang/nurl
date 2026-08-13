# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-13T03:17:04Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `741bdce07463e6cb017897f5cda68e2d9884cfe2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31663198325 |
| NURL | `v0.39.0-21-g741bdce0` |
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
| _(floor: empty program)_ | _1.810_ | _1.860_ | _2.040_ | _24.838_ | _17.562_ |
| `lcg` | **44.217** | 44.280 | 44.425 | 1813.640 | 5466.476 |
| `packet_classifier` | **63.573** | 63.685 | 63.785 | 156.565 | 4715.283 |
| `ring_write` | **47.717** | 47.800 | 47.879 | 72.976 | 6548.946 |
| `histogram_bins` | 44.813 | **44.810** | 44.917 | 74.848 | 6604.420 |
| `prefix_scan` | 24.654 | **24.615** | 24.834 | 72.333 | 4663.368 |
| `binary_search` | **35.738** | 35.888 | 45.984 | 111.234 | 6336.622 |
| `sort_window` | **30.820** | 30.951 | 32.122 | 164.868 | 11732.321 |
| `bloom_filter` | **19.875** | 20.505 | 20.845 | 2795.794 | 7994.737 |
| `hash_join` | **29.270** | 30.829 | 31.156 | 3534.934 | 8223.660 |
| `sieve` | 20.356 | **20.178** | 20.486 | 70.060 | 3692.884 |
| `fib` | **27.986** | 33.358 | 29.505 | 140.443 | 1295.591 |
| `collatz` | 14.318 | **13.911** | 13.997 | 51.818 | 750.049 |
| `matmul` | **45.234** | 46.797 | 46.060 | 83.930 | 3595.559 |
| `json_parse` | **8.901** | 9.147 | 12.241 | 38.255 | 38.672 |
| `nbody` | 46.227 | 46.272 | **44.139** | 95.851 | 3197.564 |

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
| _(floor: empty program)_ | _3.035_ | _86.396_ | _**89.431**_ | _62.454_ | _64.609_ |
| `lcg` | 3.110 | 92.531 | **95.641** | 71.181 | 71.712 |
| `packet_classifier` | 3.187 | 93.368 | **96.555** | 77.560 | 72.386 |
| `ring_write` | 3.268 | 94.601 | **97.869** | 73.310 | 73.981 |
| `histogram_bins` | 3.383 | 97.990 | **101.373** | 75.246 | 76.366 |
| `prefix_scan` | 3.447 | 99.658 | **103.105** | 77.413 | 76.724 |
| `binary_search` | 3.557 | 97.420 | **100.977** | 74.434 | 79.508 |
| `sort_window` | 3.589 | 104.282 | **107.871** | 80.737 | 83.046 |
| `bloom_filter` | 3.826 | 103.183 | **107.009** | 80.531 | 79.775 |
| `hash_join` | 6.040 | 210.401 | **216.441** | 121.838 | 116.409 |
| `sieve` | 3.464 | 101.585 | **105.049** | 83.225 | 84.501 |
| `fib` | 3.139 | 92.114 | **95.253** | 74.003 | 71.659 |
| `collatz` | 3.320 | 96.005 | **99.325** | 72.629 | 74.425 |
| `matmul` | 3.639 | 102.840 | **106.479** | 85.963 | 98.472 |
| `json_parse` | 43.627 | 518.118 | **561.745** | 127.976 | 188.718 |
| `nbody` | 4.805 | 115.974 | **120.779** | 100.275 | 97.583 |

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
