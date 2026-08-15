# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-15T09:39:01Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `76b6dc9b2d72649dd350eb697eae9119091eb87a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31877332638 |
| NURL | `v0.43.0` |
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
| _(floor: empty program)_ | _1.672_ | _1.735_ | _1.893_ | _22.639_ | _17.123_ |
| `lcg` | **39.343** | 39.475 | 39.500 | 2064.799 | 5175.648 |
| `packet_classifier` | **56.646** | 56.874 | 56.795 | 162.799 | 4376.676 |
| `ring_write` | **42.860** | 42.862 | 42.872 | 67.629 | 6563.305 |
| `histogram_bins` | **39.966** | 41.747 | 40.187 | 67.984 | 6087.908 |
| `prefix_scan` | **21.914** | 22.071 | 22.229 | 66.567 | 4611.928 |
| `binary_search` | **36.712** | 38.791 | 43.594 | 107.971 | 5992.919 |
| `sort_window` | **27.070** | 27.798 | 27.442 | 198.654 | 12391.888 |
| `bloom_filter` | **18.073** | 18.312 | 18.547 | 2878.361 | 7664.059 |
| `hash_join` | **28.447** | 31.092 | 30.416 | 3503.132 | 8232.721 |
| `sieve` | 21.196 | **20.538** | 20.686 | 67.921 | 3154.273 |
| `fib` | **25.342** | 30.200 | 28.274 | 132.784 | 1378.121 |
| `collatz` | 12.553 | **12.542** | 12.676 | 52.090 | 729.208 |
| `matmul` | **33.804** | 33.932 | 33.995 | 78.330 | 3242.534 |
| `json_parse` | **9.108** | 9.386 | 11.845 | 36.968 | 38.130 |
| `nbody` | **25.206** | 40.888 | 39.371 | 103.878 | 3103.157 |

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
| _(floor: empty program)_ | _2.814_ | _93.577_ | _**96.391**_ | _60.068_ | _59.283_ | _62.719_ |
| `lcg` | 2.980 | 94.446 | **97.426** | 59.704 | 67.867 | 72.814 |
| `packet_classifier` | 3.077 | 98.510 | **101.587** | 62.037 | 71.944 | 71.231 |
| `ring_write` | 3.231 | 100.211 | **103.442** | 62.056 | 73.448 | 74.669 |
| `histogram_bins` | 3.260 | 118.454 | **121.714** | 60.093 | 72.701 | 76.082 |
| `prefix_scan` | 3.293 | 104.260 | **107.553** | 61.838 | 75.560 | 74.344 |
| `binary_search` | 3.574 | 113.118 | **116.692** | 64.377 | 71.966 | 79.018 |
| `sort_window` | 3.516 | 111.035 | **114.551** | 62.033 | 78.690 | 80.952 |
| `bloom_filter` | 3.723 | 108.398 | **112.121** | 62.041 | 80.563 | 78.889 |
| `hash_join` | 6.096 | 259.206 | **265.302** | 63.936 | 125.324 | 113.183 |
| `sieve` | 3.257 | 102.646 | **105.903** | 61.132 | 81.948 | 79.759 |
| `fib` | 3.007 | 95.429 | **98.436** | 61.081 | 68.646 | 68.334 |
| `collatz` | 3.189 | 99.373 | **102.562** | 61.142 | 71.384 | 72.511 |
| `matmul` | 3.565 | 106.998 | **110.563** | 62.262 | 84.457 | 96.612 |
| `json_parse` | 49.114 | 437.582 | **486.696** | 107.442 | 125.323 | 180.782 |
| `nbody` | 4.771 | 127.725 | **132.496** | 61.585 | 98.110 | 94.958 |

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
