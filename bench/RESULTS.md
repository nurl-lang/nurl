# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-17T12:45:28Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `dd750e1005e69a9f33b13e9fc5c47ce8a9e345a2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32031037822 |
| NURL | `v0.44.2-14-gdd750e10` |
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
| _(floor: empty program)_ | _1.829_ | _1.881_ | _2.028_ | _24.165_ | _18.235_ |
| `lcg` | **44.350** | 44.363 | 44.548 | 1820.304 | 5327.692 |
| `packet_classifier` | **63.811** | 63.964 | 63.975 | 158.004 | 4706.370 |
| `ring_write` | **47.907** | 48.064 | 48.067 | 74.089 | 6746.619 |
| `histogram_bins` | 45.027 | **44.992** | 45.244 | 76.566 | 6336.119 |
| `prefix_scan` | **24.612** | 24.773 | 25.008 | 71.727 | 4724.218 |
| `binary_search` | **34.326** | 35.962 | 46.319 | 114.106 | 6490.633 |
| `sort_window` | **30.239** | 30.997 | 30.695 | 166.658 | 10942.145 |
| `bloom_filter` | **19.969** | 20.614 | 20.867 | 2768.694 | 7743.313 |
| `hash_join` | **27.797** | 31.248 | 31.556 | 3480.635 | 8058.481 |
| `sieve` | 20.893 | **20.669** | 20.833 | 72.647 | 3665.600 |
| `fib` | **28.297** | 33.424 | 29.469 | 143.487 | 1285.569 |
| `collatz` | **14.004** | 14.080 | 14.156 | 53.086 | 759.482 |
| `matmul` | **46.054** | 46.435 | 46.275 | 85.068 | 3594.896 |
| `json_parse` | **8.949** | 9.143 | 12.283 | 40.116 | 39.059 |
| `nbody` | **27.045** | 46.433 | 44.328 | 96.885 | 3166.030 |

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
| _(floor: empty program)_ | _3.304_ | _101.630_ | _**104.934**_ | _67.763_ | _67.838_ | _67.663_ |
| `lcg` | 3.373 | 102.436 | **105.809** | 65.802 | 75.610 | 74.512 |
| `packet_classifier` | 3.490 | 104.742 | **108.232** | 66.728 | 83.636 | 75.642 |
| `ring_write` | 3.570 | 104.169 | **107.739** | 65.323 | 76.946 | 76.708 |
| `histogram_bins` | 3.620 | 127.898 | **131.518** | 67.991 | 78.252 | 77.849 |
| `prefix_scan` | 3.648 | 109.092 | **112.740** | 66.732 | 82.395 | 80.788 |
| `binary_search` | 3.867 | 114.576 | **118.443** | 65.889 | 76.463 | 82.557 |
| `sort_window` | 3.970 | 120.217 | **124.187** | 67.010 | 86.319 | 85.556 |
| `bloom_filter` | 4.103 | 113.653 | **117.756** | 66.975 | 86.762 | 83.918 |
| `hash_join` | 6.712 | 257.773 | **264.485** | 70.491 | 125.431 | 118.636 |
| `sieve` | 3.790 | 110.237 | **114.027** | 67.112 | 88.392 | 88.041 |
| `fib` | 3.516 | 106.380 | **109.896** | 67.993 | 76.501 | 74.438 |
| `collatz` | 3.646 | 109.911 | **113.557** | 67.023 | 77.752 | 76.477 |
| `matmul` | 4.107 | 115.358 | **119.465** | 69.847 | 89.093 | 101.943 |
| `json_parse` | 51.485 | 423.746 | **475.231** | 115.992 | 130.850 | 192.001 |
| `nbody` | 5.400 | 139.853 | **145.253** | 69.665 | 104.944 | 101.175 |

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
