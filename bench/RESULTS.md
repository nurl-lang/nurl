# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-30T20:09:13Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377692 KiB |
| Commit | `3e731f103449911e0c68dcddfe192c02a45ec91d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30577523941 |
| NURL | `v0.29.0-62-g3e731f1` |
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
| _(floor: empty program)_ | _1.667_ | _1.725_ | _1.860_ | _21.287_ | _16.797_ |
| `lcg` | **39.368** | 39.422 | 39.595 | 1879.795 | 5210.408 |
| `packet_classifier` | **56.432** | 56.547 | 56.681 | 161.093 | 4744.907 |
| `ring_write` | 42.502 | **42.433** | 42.568 | 65.802 | 6963.174 |
| `histogram_bins` | **39.834** | 41.510 | 40.054 | 67.125 | 6189.066 |
| `prefix_scan` | **21.994** | 22.043 | 22.188 | 65.976 | 4512.295 |
| `binary_search` | 39.771 | **38.360** | 43.150 | 105.882 | 6013.110 |
| `sort_window` | 27.416 | 27.518 | **27.007** | 197.338 | 11807.441 |
| `bloom_filter` | **18.174** | 18.376 | 18.580 | 2848.457 | 7578.774 |
| `hash_join` | **28.087** | 30.102 | 29.971 | 3426.247 | 8762.667 |
| `sieve` | 19.159 | 18.426 | **18.190** | 65.498 | 3246.633 |
| `fib` | **25.346** | 30.079 | 28.351 | 131.931 | 1390.488 |
| `collatz` | 12.521 | **12.464** | 12.582 | 49.590 | 725.744 |
| `matmul` | **33.709** | 33.841 | 33.899 | 75.458 | 3191.334 |
| `json_parse` | **8.592** | 8.973 | 11.927 | 35.415 | 37.906 |
| `nbody` | 41.099 | 41.141 | **39.243** | 99.961 | 3074.458 |

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
| _(floor: empty program)_ | _3.579_ | _79.911_ | _**83.490**_ | _59.085_ | _60.021_ |
| `lcg` | 3.158 | 82.252 | **85.410** | 65.090 | 69.353 |
| `packet_classifier` | 3.301 | 87.537 | **90.838** | 67.295 | 67.830 |
| `ring_write` | 3.460 | 86.352 | **89.812** | 66.314 | 68.829 |
| `histogram_bins` | 3.580 | 88.795 | **92.375** | 68.756 | 72.132 |
| `prefix_scan` | 3.680 | 93.459 | **97.139** | 72.245 | 71.203 |
| `binary_search` | 3.937 | 91.286 | **95.223** | 68.973 | 75.555 |
| `sort_window` | 4.063 | 98.254 | **102.317** | 75.788 | 78.440 |
| `bloom_filter` | 4.377 | 94.090 | **98.467** | 75.274 | 78.838 |
| `hash_join` | 8.800 | 209.202 | **218.002** | 117.940 | 109.874 |
| `sieve` | 3.693 | 89.612 | **93.305** | 78.838 | 79.112 |
| `fib` | 3.221 | 84.108 | **87.329** | 65.958 | 66.746 |
| `collatz` | 3.557 | 87.000 | **90.557** | 66.883 | 70.177 |
| `matmul` | 4.323 | 94.752 | **99.075** | 82.314 | 94.729 |
| `json_parse` | 74.172 | 732.632 | **806.804** | 126.009 | 178.516 |
| `nbody` | 6.616 | 106.449 | **113.065** | 96.229 | 92.149 |

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
