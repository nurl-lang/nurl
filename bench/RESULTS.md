# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-09T14:58:09Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `2bfc8068f5cdc00c8d1324bf46164b028867f5d4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31319632496 |
| NURL | `v0.36.0-24-g2bfc8068` |
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
| _(floor: empty program)_ | _1.671_ | _1.710_ | _1.858_ | _23.596_ | _17.221_ |
| `lcg` | **39.172** | 39.278 | 39.372 | 1873.332 | 5261.653 |
| `packet_classifier` | **56.440** | 56.506 | 56.671 | 162.777 | 4369.069 |
| `ring_write` | **42.330** | 42.483 | 42.499 | 66.633 | 6173.818 |
| `histogram_bins` | **39.853** | 41.396 | 39.909 | 66.975 | 6035.537 |
| `prefix_scan` | **21.913** | 21.944 | 22.123 | 65.108 | 4757.485 |
| `binary_search` | 39.972 | **38.476** | 43.525 | 106.288 | 5947.017 |
| `sort_window` | 27.404 | 27.503 | **27.015** | 197.417 | 11283.139 |
| `bloom_filter` | **18.030** | 18.247 | 18.485 | 2821.761 | 7858.144 |
| `hash_join` | **28.009** | 30.229 | 30.077 | 3424.444 | 8124.212 |
| `sieve` | 18.797 | **18.291** | 18.466 | 65.634 | 3176.093 |
| `fib` | **25.324** | 30.103 | 28.436 | 131.658 | 1340.476 |
| `collatz` | 12.524 | **12.508** | 12.666 | 50.637 | 714.186 |
| `matmul` | **33.596** | 33.651 | 33.988 | 76.658 | 3064.997 |
| `json_parse` | 42.425 | **8.942** | 11.723 | 36.338 | 37.779 |
| `nbody` | 41.052 | 41.189 | **39.256** | 101.958 | 3040.506 |

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
| _(floor: empty program)_ | _2.915_ | _81.246_ | _**84.161**_ | _59.315_ | _60.699_ |
| `lcg` | 2.783 | 86.690 | **89.473** | 67.012 | 69.657 |
| `packet_classifier` | 2.844 | 88.809 | **91.653** | 70.625 | 66.407 |
| `ring_write` | 3.052 | 91.641 | **94.693** | 70.929 | 71.129 |
| `histogram_bins` | 3.020 | 94.114 | **97.134** | 71.731 | 72.562 |
| `prefix_scan` | 3.068 | 94.925 | **97.993** | 72.782 | 71.313 |
| `binary_search` | 3.265 | 92.443 | **95.708** | 70.391 | 74.634 |
| `sort_window` | 3.214 | 102.028 | **105.242** | 76.555 | 78.963 |
| `bloom_filter` | 3.440 | 99.230 | **102.670** | 78.549 | 76.420 |
| `hash_join` | 5.627 | 212.692 | **218.319** | 122.262 | 111.260 |
| `sieve` | 3.065 | 94.768 | **97.833** | 81.017 | 80.067 |
| `fib` | 2.813 | 88.190 | **91.003** | 67.521 | 67.973 |
| `collatz` | 2.982 | 91.887 | **94.869** | 69.658 | 70.465 |
| `matmul` | 3.301 | 98.840 | **102.141** | 81.960 | 93.122 |
| `json_parse` | 43.013 | 543.732 | **586.745** | 125.020 | 177.750 |
| `nbody` | 4.397 | 108.704 | **113.101** | 98.068 | 92.307 |

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
