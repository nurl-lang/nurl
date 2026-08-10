# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-10T18:18:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `a68a25c4871e135ddd3b85ba05ec7c1eebd46ac3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31417965177 |
| NURL | `v0.36.0-69-ga68a25c4` |
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
| _(floor: empty program)_ | _1.711_ | _1.727_ | _1.906_ | _24.394_ | _17.064_ |
| `lcg` | **39.247** | 39.309 | 39.362 | 1876.582 | 5119.080 |
| `packet_classifier` | **56.448** | 56.458 | 56.645 | 162.133 | 4309.806 |
| `ring_write` | **42.384** | 42.398 | 42.495 | 66.961 | 6909.215 |
| `histogram_bins` | **39.758** | 41.483 | 39.925 | 66.447 | 6339.373 |
| `prefix_scan` | **21.924** | 22.004 | 22.296 | 66.684 | 4455.507 |
| `binary_search` | 39.967 | **38.515** | 43.362 | 106.631 | 6369.693 |
| `sort_window` | 27.515 | 27.450 | **26.904** | 197.513 | 11446.949 |
| `bloom_filter` | **18.081** | 18.234 | 18.502 | 2854.092 | 7661.193 |
| `hash_join` | **27.951** | 30.023 | 29.985 | 3431.454 | 8311.029 |
| `sieve` | 18.437 | 18.222 | **18.110** | 66.171 | 3456.572 |
| `fib` | **25.362** | 30.103 | 28.394 | 131.838 | 1341.164 |
| `collatz` | 12.511 | **12.485** | 12.547 | 49.499 | 722.402 |
| `matmul` | **33.498** | 33.499 | 33.874 | 77.544 | 3197.883 |
| `json_parse` | 42.190 | **8.872** | 11.714 | 35.488 | 37.362 |
| `nbody` | 40.899 | 40.969 | **39.079** | 100.063 | 3159.699 |

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
| _(floor: empty program)_ | _3.053_ | _85.748_ | _**88.801**_ | _58.363_ | _71.719_ |
| `lcg` | 2.845 | 85.620 | **88.465** | 66.314 | 68.691 |
| `packet_classifier` | 2.909 | 88.848 | **91.757** | 67.775 | 70.199 |
| `ring_write` | 3.054 | 89.966 | **93.020** | 68.687 | 71.324 |
| `histogram_bins` | 3.071 | 91.765 | **94.836** | 70.339 | 73.045 |
| `prefix_scan` | 3.133 | 95.272 | **98.405** | 73.058 | 73.081 |
| `binary_search` | 3.208 | 92.338 | **95.546** | 72.025 | 90.455 |
| `sort_window` | 3.250 | 105.242 | **108.492** | 77.687 | 77.505 |
| `bloom_filter` | 3.433 | 96.266 | **99.699** | 77.135 | 77.329 |
| `hash_join` | 5.520 | 212.683 | **218.203** | 121.158 | 111.714 |
| `sieve` | 3.035 | 95.793 | **98.828** | 79.443 | 89.121 |
| `fib` | 2.881 | 87.068 | **89.949** | 66.974 | 69.966 |
| `collatz` | 2.943 | 89.477 | **92.420** | 69.193 | 74.592 |
| `matmul` | 3.311 | 97.572 | **100.883** | 80.828 | 93.741 |
| `json_parse` | 41.689 | 552.899 | **594.588** | 123.954 | 180.493 |
| `nbody` | 4.501 | 110.082 | **114.583** | 97.122 | 95.576 |

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
