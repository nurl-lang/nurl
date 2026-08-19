# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-19T19:15:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `88b1219ca400f07173f053b9aee6b4e8d560beab` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32291528484 |
| NURL | `v0.45.0-12-g88b1219c` |
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
| _(floor: empty program)_ | _1.807_ | _1.848_ | _1.986_ | _25.633_ | _17.679_ |
| `lcg` | 44.351 | **44.334** | 44.440 | 1815.457 | 5568.984 |
| `packet_classifier` | **63.668** | 63.719 | 63.907 | 157.734 | 4525.974 |
| `ring_write` | **47.747** | 47.828 | 48.008 | 73.315 | 6629.586 |
| `histogram_bins` | **44.715** | 44.853 | 44.983 | 74.311 | 6594.927 |
| `prefix_scan` | 24.672 | **24.656** | 24.813 | 70.519 | 4684.972 |
| `binary_search` | **33.523** | 35.923 | 46.201 | 111.505 | 6657.828 |
| `sort_window` | **30.236** | 30.994 | 30.396 | 166.131 | 11000.476 |
| `bloom_filter` | **19.968** | 20.513 | 20.878 | 2701.801 | 7643.407 |
| `hash_join` | **27.916** | 30.849 | 31.258 | 3420.131 | 8250.840 |
| `sieve` | 20.429 | **20.212** | 20.301 | 71.103 | 3632.215 |
| `fib` | **28.119** | 33.457 | 29.487 | 141.971 | 1282.136 |
| `collatz` | 13.927 | **13.925** | 14.051 | 50.555 | 753.573 |
| `matmul` | **45.390** | 46.778 | 45.673 | 82.902 | 3415.751 |
| `json_parse` | **8.906** | 9.137 | 12.254 | 38.923 | 37.862 |
| `nbody` | **26.934** | 46.372 | 44.181 | 96.246 | 3220.909 |

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
| _(floor: empty program)_ | _3.197_ | _98.689_ | _**101.886**_ | _62.659_ | _62.779_ | _65.778_ |
| `lcg` | 3.311 | 99.185 | **102.496** | 62.539 | 71.174 | 72.462 |
| `packet_classifier` | 3.434 | 99.887 | **103.321** | 63.612 | 72.803 | 73.338 |
| `ring_write` | 3.563 | 101.785 | **105.348** | 63.469 | 73.777 | 73.676 |
| `histogram_bins` | 3.661 | 119.542 | **123.203** | 63.750 | 75.897 | 77.097 |
| `prefix_scan` | 3.654 | 104.690 | **108.344** | 63.419 | 77.585 | 76.035 |
| `binary_search` | 3.842 | 108.745 | **112.587** | 63.822 | 73.815 | 78.268 |
| `sort_window` | 3.873 | 110.760 | **114.633** | 63.392 | 80.253 | 83.633 |
| `bloom_filter` | 4.083 | 108.516 | **112.599** | 64.071 | 80.944 | 79.347 |
| `hash_join` | 6.648 | 248.739 | **255.387** | 66.246 | 121.317 | 115.072 |
| `sieve` | 3.694 | 104.125 | **107.819** | 63.987 | 82.174 | 87.384 |
| `fib` | 3.405 | 100.175 | **103.580** | 63.415 | 71.492 | 71.664 |
| `collatz` | 3.578 | 102.507 | **106.085** | 63.092 | 73.248 | 75.386 |
| `matmul` | 3.937 | 105.779 | **109.716** | 63.921 | 85.009 | 96.491 |
| `json_parse` | 52.625 | 413.853 | **466.478** | 118.066 | 124.026 | 185.590 |
| `nbody` | 5.273 | 130.094 | **135.367** | 65.279 | 98.265 | 97.510 |

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
