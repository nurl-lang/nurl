# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-05T19:07:44Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `be22865a6f998648ecb95cce68319afc700c5350` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31037590398 |
| NURL | `v0.33.0-32-gbe22865a` |
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
| _(floor: empty program)_ | _1.694_ | _1.756_ | _1.922_ | _24.332_ | _18.025_ |
| `lcg` | 39.584 | **39.509** | 39.552 | 1877.962 | 5067.175 |
| `packet_classifier` | **56.779** | 56.800 | 56.884 | 163.265 | 4503.562 |
| `ring_write` | 42.763 | **42.651** | 42.879 | 67.471 | 6101.590 |
| `histogram_bins` | **39.952** | 41.732 | 40.277 | 69.449 | 6066.868 |
| `prefix_scan` | **22.058** | 22.185 | 22.315 | 66.330 | 4502.631 |
| `binary_search` | 40.306 | **38.571** | 43.572 | 107.505 | 6412.871 |
| `sort_window` | 27.806 | 27.781 | **27.252** | 200.635 | 12825.177 |
| `bloom_filter` | **18.409** | 18.567 | 18.823 | 2868.160 | 7567.427 |
| `hash_join` | **28.353** | 30.652 | 30.431 | 3455.375 | 8268.397 |
| `sieve` | 22.099 | 21.709 | **21.414** | 70.160 | 3264.059 |
| `fib` | **25.667** | 30.555 | 28.822 | 135.659 | 1385.896 |
| `collatz` | **12.694** | 12.764 | 13.201 | 52.999 | 711.484 |
| `matmul` | 34.589 | **34.166** | 34.468 | 78.991 | 3222.001 |
| `json_parse` | **9.166** | 9.480 | 12.184 | 39.218 | 41.450 |
| `nbody` | 41.183 | 41.268 | **39.415** | 101.080 | 4479.931 |

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
| _(floor: empty program)_ | _2.805_ | _86.527_ | _**89.332**_ | _61.075_ | _69.001_ |
| `lcg` | 2.841 | 93.688 | **96.529** | 69.438 | 72.481 |
| `packet_classifier` | 2.893 | 93.403 | **96.296** | 72.287 | 72.224 |
| `ring_write` | 2.949 | 93.631 | **96.580** | 71.626 | 72.150 |
| `histogram_bins` | 3.003 | 93.622 | **96.625** | 70.979 | 71.981 |
| `prefix_scan` | 3.214 | 101.308 | **104.522** | 77.243 | 76.399 |
| `binary_search` | 3.158 | 97.328 | **100.486** | 72.559 | 76.929 |
| `sort_window` | 3.216 | 104.842 | **108.058** | 78.269 | 83.830 |
| `bloom_filter` | 3.411 | 101.369 | **104.780** | 80.217 | 78.419 |
| `hash_join` | 5.561 | 220.006 | **225.567** | 125.002 | 118.022 |
| `sieve` | 3.113 | 100.145 | **103.258** | 82.608 | 86.353 |
| `fib` | 2.945 | 95.476 | **98.421** | 72.505 | 73.070 |
| `collatz` | 3.058 | 97.193 | **100.251** | 73.638 | 77.849 |
| `matmul` | 3.481 | 113.188 | **116.669** | 86.343 | 99.702 |
| `json_parse` | 41.160 | 550.515 | **591.675** | 129.072 | 197.833 |
| `nbody` | 4.457 | 119.725 | **124.182** | 98.660 | 96.343 |

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
