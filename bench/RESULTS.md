# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-14T15:31:45Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `99b99e85cd481576106ab568683bfdfaaf0dfa0e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31814541391 |
| NURL | `v0.42.0-9-g99b99e85` |
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
| _(floor: empty program)_ | _1.836_ | _1.905_ | _2.048_ | _24.662_ | _17.993_ |
| `lcg` | **44.392** | 44.441 | 44.577 | 1823.591 | 5297.040 |
| `packet_classifier` | **63.829** | 63.857 | 64.110 | 158.353 | 4749.181 |
| `ring_write` | **47.909** | 47.974 | 48.076 | 73.507 | 6721.518 |
| `histogram_bins` | **44.894** | 44.946 | 45.055 | 75.526 | 6267.849 |
| `prefix_scan` | **24.701** | 24.728 | 24.938 | 71.348 | 5098.039 |
| `binary_search` | **34.023** | 36.102 | 46.301 | 113.214 | 6485.146 |
| `sort_window` | **30.227** | 31.021 | 30.375 | 164.401 | 13232.238 |
| `bloom_filter` | **19.950** | 20.607 | 20.907 | 2765.977 | 8271.908 |
| `hash_join` | **27.904** | 31.056 | 31.219 | 3466.584 | 8196.937 |
| `sieve` | 21.047 | **20.555** | 21.061 | 71.969 | 3419.216 |
| `fib` | **28.182** | 33.475 | 29.603 | 143.921 | 1299.548 |
| `collatz` | **13.961** | 13.975 | 14.109 | 52.437 | 758.191 |
| `matmul` | **45.239** | 46.361 | 45.813 | 84.870 | 4067.418 |
| `json_parse` | **9.004** | 9.137 | 12.263 | 38.710 | 38.709 |
| `nbody` | **27.025** | 46.500 | 44.346 | 95.173 | 3301.562 |

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
| _(floor: empty program)_ | _3.123_ | _101.802_ | _**104.925**_ | _66.538_ | _66.813_ | _67.081_ |
| `lcg` | 3.237 | 100.943 | **104.180** | 64.644 | 73.819 | 74.864 |
| `packet_classifier` | 3.324 | 102.028 | **105.352** | 65.821 | 76.106 | 75.122 |
| `ring_write` | 3.437 | 102.774 | **106.211** | 65.547 | 75.811 | 76.552 |
| `histogram_bins` | 3.573 | 128.948 | **132.521** | 69.528 | 81.044 | 79.396 |
| `prefix_scan` | 3.580 | 110.401 | **113.981** | 65.857 | 79.282 | 78.597 |
| `binary_search` | 3.679 | 113.857 | **117.536** | 66.282 | 76.467 | 80.970 |
| `sort_window` | 3.778 | 117.590 | **121.368** | 67.232 | 83.807 | 85.767 |
| `bloom_filter` | 4.028 | 112.735 | **116.763** | 66.435 | 83.698 | 81.680 |
| `hash_join` | 6.368 | 255.644 | **262.012** | 68.180 | 123.253 | 119.693 |
| `sieve` | 3.598 | 108.633 | **112.231** | 66.988 | 86.995 | 87.086 |
| `fib` | 3.316 | 105.279 | **108.595** | 67.927 | 74.938 | 76.054 |
| `collatz` | 3.499 | 109.285 | **112.784** | 68.914 | 79.142 | 78.371 |
| `matmul` | 3.833 | 111.579 | **115.412** | 66.626 | 88.772 | 100.567 |
| `json_parse` | 48.246 | 422.437 | **470.683** | 113.675 | 131.069 | 195.086 |
| `nbody` | 5.088 | 137.290 | **142.378** | 68.435 | 102.592 | 102.064 |

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
