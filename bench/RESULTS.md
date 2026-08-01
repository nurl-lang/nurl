# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-01T14:15:09Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373456 KiB |
| Commit | `6336cdaba29bc9f12fad2a4c5a57792715a018fb` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30703212001 |
| NURL | `v0.30.0-22-g6336cda` |
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
| _(floor: empty program)_ | _1.726_ | _1.817_ | _1.946_ | _24.309_ | _18.560_ |
| `lcg` | 39.747 | **39.734** | 39.857 | 1882.017 | 5202.911 |
| `packet_classifier` | **56.843** | 56.856 | 56.941 | 163.714 | 4417.634 |
| `ring_write` | **42.733** | 42.813 | 42.823 | 67.509 | 6165.614 |
| `histogram_bins` | **40.064** | 41.666 | 40.307 | 68.498 | 6607.971 |
| `prefix_scan` | **22.269** | 22.305 | 22.461 | 67.018 | 4612.350 |
| `binary_search` | 40.175 | **38.778** | 43.807 | 108.336 | 6169.028 |
| `sort_window` | 27.758 | 27.782 | **27.321** | 198.662 | 11171.786 |
| `bloom_filter` | **18.387** | 18.619 | 18.867 | 2836.918 | 7286.079 |
| `hash_join` | **28.482** | 30.577 | 30.518 | 3444.419 | 8257.397 |
| `sieve` | 18.891 | 18.952 | **18.839** | 67.934 | 3148.655 |
| `fib` | **25.788** | 30.712 | 28.645 | 133.272 | 1344.434 |
| `collatz` | 12.789 | **12.661** | 12.858 | 52.479 | 719.075 |
| `matmul` | 34.167 | **34.086** | 34.272 | 79.077 | 3251.835 |
| `json_parse` | **9.043** | 9.213 | 12.423 | 37.693 | 40.411 |
| `nbody` | 41.211 | 41.420 | **39.577** | 104.408 | 2968.284 |

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
| _(floor: empty program)_ | _2.847_ | _84.816_ | _**87.663**_ | _60.997_ | _64.610_ |
| `lcg` | 2.814 | 90.327 | **93.141** | 70.782 | 73.111 |
| `packet_classifier` | 2.997 | 92.228 | **95.225** | 72.889 | 72.333 |
| `ring_write` | 3.013 | 93.760 | **96.773** | 72.695 | 75.773 |
| `histogram_bins` | 3.109 | 96.133 | **99.242** | 74.350 | 77.666 |
| `prefix_scan` | 3.165 | 98.328 | **101.493** | 77.480 | 77.418 |
| `binary_search` | 3.293 | 97.319 | **100.612** | 74.308 | 80.618 |
| `sort_window` | 3.362 | 103.197 | **106.559** | 79.912 | 84.775 |
| `bloom_filter` | 3.564 | 102.462 | **106.026** | 81.673 | 79.619 |
| `hash_join` | 5.645 | 219.500 | **225.145** | 124.869 | 115.840 |
| `sieve` | 3.237 | 98.283 | **101.520** | 84.494 | 89.956 |
| `fib` | 2.893 | 90.225 | **93.118** | 70.860 | 71.411 |
| `collatz` | 3.057 | 94.138 | **97.195** | 73.059 | 74.634 |
| `matmul` | 3.397 | 101.874 | **105.271** | 85.686 | 99.820 |
| `json_parse` | 41.263 | 541.275 | **582.538** | 134.513 | 190.911 |
| `nbody` | 4.528 | 115.910 | **120.438** | 102.974 | 99.323 |

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
