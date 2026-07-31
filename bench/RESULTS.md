# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-31T20:37:08Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `64195f4e6054dfb8169742ec32e0a55e66c85f8c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30663239965 |
| NURL | `v0.29.0-104-g64195f4` |
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
| _(floor: empty program)_ | _1.675_ | _1.724_ | _1.900_ | _24.685_ | _17.172_ |
| `lcg` | **39.268** | 39.424 | 39.461 | 1897.470 | 5066.950 |
| `packet_classifier` | **56.436** | 56.614 | 56.646 | 162.192 | 4429.265 |
| `ring_write` | **42.548** | 42.578 | 42.747 | 67.794 | 6213.794 |
| `histogram_bins` | **39.885** | 41.601 | 40.025 | 66.622 | 6190.257 |
| `prefix_scan` | **21.894** | 21.899 | 22.046 | 66.241 | 5126.679 |
| `binary_search` | 39.676 | **38.402** | 43.413 | 107.087 | 6127.098 |
| `sort_window` | 27.332 | 27.515 | **26.926** | 197.779 | 12452.790 |
| `bloom_filter` | **18.032** | 18.260 | 18.542 | 2835.269 | 7779.827 |
| `hash_join` | **28.129** | 30.192 | 30.052 | 3407.033 | 8368.042 |
| `sieve` | 18.691 | 18.215 | **18.094** | 66.085 | 3323.568 |
| `fib` | **25.537** | 30.208 | 28.321 | 132.200 | 1359.120 |
| `collatz` | 12.451 | **12.433** | 12.598 | 48.964 | 712.120 |
| `matmul` | **33.587** | 33.788 | 33.890 | 76.011 | 3017.325 |
| `json_parse` | **8.638** | 8.790 | 11.705 | 35.583 | 37.757 |
| `nbody` | 41.110 | 40.935 | **39.106** | 100.893 | 3066.101 |

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
| _(floor: empty program)_ | _2.613_ | _81.616_ | _**84.229**_ | _57.819_ | _61.549_ |
| `lcg` | 2.781 | 84.695 | **87.476** | 66.914 | 68.212 |
| `packet_classifier` | 2.857 | 87.575 | **90.432** | 73.181 | 67.556 |
| `ring_write` | 2.972 | 88.994 | **91.966** | 69.658 | 69.047 |
| `histogram_bins` | 3.092 | 95.743 | **98.835** | 73.119 | 71.914 |
| `prefix_scan` | 3.227 | 92.588 | **95.815** | 72.603 | 70.478 |
| `binary_search` | 3.377 | 91.899 | **95.276** | 69.874 | 72.794 |
| `sort_window` | 3.337 | 97.470 | **100.807** | 75.372 | 77.625 |
| `bloom_filter` | 3.600 | 97.332 | **100.932** | 76.236 | 73.804 |
| `hash_join` | 6.834 | 211.889 | **218.723** | 121.240 | 108.577 |
| `sieve` | 3.155 | 92.914 | **96.069** | 79.388 | 78.917 |
| `fib` | 2.793 | 85.159 | **87.952** | 67.329 | 66.516 |
| `collatz` | 3.005 | 91.188 | **94.193** | 70.645 | 68.358 |
| `matmul` | 3.526 | 96.329 | **99.855** | 80.227 | 91.057 |
| `json_parse` | 53.971 | 515.653 | **569.624** | 123.836 | 177.090 |
| `nbody` | 4.950 | 106.595 | **111.545** | 96.527 | 91.906 |

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
