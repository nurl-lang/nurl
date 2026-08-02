# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-02T06:21:00Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373460 KiB |
| Commit | `486a0a19750eae563b339afd563e7db52fde10cf` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30735612927 |
| NURL | `v0.30.0-40-g486a0a19` |
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
| _(floor: empty program)_ | _1.667_ | _1.732_ | _1.909_ | _26.281_ | _17.587_ |
| `lcg` | **39.264** | 39.425 | 39.483 | 1879.238 | 5136.115 |
| `packet_classifier` | **56.617** | 56.673 | 56.748 | 162.830 | 4328.436 |
| `ring_write` | 42.599 | **42.582** | 42.773 | 67.581 | 6394.447 |
| `histogram_bins` | **39.833** | 41.703 | 40.160 | 68.427 | 6222.314 |
| `prefix_scan` | **22.203** | 22.270 | 22.347 | 67.153 | 4640.491 |
| `binary_search` | 40.177 | **38.818** | 43.443 | 108.711 | 6559.490 |
| `sort_window` | 27.430 | 27.539 | **26.996** | 198.090 | 11958.551 |
| `bloom_filter` | **18.224** | 18.504 | 18.868 | 2831.084 | 7388.295 |
| `hash_join` | **28.027** | 30.320 | 30.110 | 3421.741 | 8474.819 |
| `sieve` | 21.546 | **20.887** | 21.178 | 68.585 | 3233.611 |
| `fib` | **25.568** | 30.423 | 28.734 | 132.281 | 1362.582 |
| `collatz` | **12.481** | 12.545 | 12.693 | 50.795 | 715.128 |
| `matmul` | **33.900** | 33.981 | 34.143 | 77.698 | 3228.296 |
| `json_parse` | **8.727** | 8.968 | 11.817 | 35.668 | 38.082 |
| `nbody` | 41.272 | 41.277 | **39.348** | 100.826 | 3138.395 |

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
| _(floor: empty program)_ | _2.817_ | _84.413_ | _**87.230**_ | _61.956_ | _63.142_ |
| `lcg` | 2.788 | 89.313 | **92.101** | 71.335 | 70.154 |
| `packet_classifier` | 2.856 | 88.913 | **91.769** | 69.860 | 70.105 |
| `ring_write` | 2.898 | 88.252 | **91.150** | 72.815 | 71.680 |
| `histogram_bins` | 3.019 | 91.921 | **94.940** | 73.091 | 75.661 |
| `prefix_scan` | 3.013 | 92.238 | **95.251** | 75.495 | 74.994 |
| `binary_search` | 3.166 | 95.871 | **99.037** | 74.206 | 76.698 |
| `sort_window` | 3.215 | 102.152 | **105.367** | 80.529 | 79.814 |
| `bloom_filter` | 3.478 | 101.645 | **105.123** | 80.210 | 79.038 |
| `hash_join` | 5.459 | 217.014 | **222.473** | 123.112 | 114.378 |
| `sieve` | 3.081 | 97.516 | **100.597** | 80.378 | 80.359 |
| `fib` | 2.826 | 88.107 | **90.933** | 70.113 | 68.944 |
| `collatz` | 2.992 | 92.254 | **95.246** | 70.544 | 70.801 |
| `matmul` | 3.253 | 96.581 | **99.834** | 82.886 | 93.762 |
| `json_parse` | 40.741 | 522.381 | **563.122** | 128.488 | 181.940 |
| `nbody` | 4.387 | 110.410 | **114.797** | 100.794 | 94.541 |

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
