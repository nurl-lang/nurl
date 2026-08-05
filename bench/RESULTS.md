# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-05T10:02:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `b842ff646ad6b535ba29b698299f18d4ea29d6c9` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30995463869 |
| NURL | `v0.33.0-8-gb842ff64` |
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
| _(floor: empty program)_ | _1.711_ | _1.802_ | _1.940_ | _24.869_ | _18.365_ |
| `lcg` | **39.574** | 39.631 | 39.631 | 1885.356 | 5183.479 |
| `packet_classifier` | **56.634** | 56.688 | 56.829 | 163.219 | 4524.137 |
| `ring_write` | **42.644** | 42.768 | 42.790 | 66.946 | 6200.448 |
| `histogram_bins` | **40.000** | 41.502 | 40.078 | 68.934 | 6306.367 |
| `prefix_scan` | **22.126** | 22.251 | 22.247 | 66.882 | 4652.299 |
| `binary_search` | 40.192 | **38.630** | 43.687 | 107.884 | 6036.323 |
| `sort_window` | 27.553 | 27.677 | **27.115** | 200.621 | 11563.987 |
| `bloom_filter` | **18.205** | 18.402 | 18.832 | 2844.983 | 7501.262 |
| `hash_join` | **28.393** | 30.235 | 30.142 | 3439.143 | 8386.075 |
| `sieve` | 18.821 | **18.414** | 20.478 | 67.383 | 3372.231 |
| `fib` | **25.384** | 30.309 | 28.592 | 132.675 | 1346.166 |
| `collatz` | 12.521 | **12.447** | 12.693 | 50.384 | 714.035 |
| `matmul` | 34.208 | **34.134** | 34.163 | 77.922 | 3125.153 |
| `json_parse` | 9.115 | **8.945** | 11.870 | 36.271 | 39.351 |
| `nbody` | 41.312 | 41.186 | **39.308** | 101.883 | 2995.785 |

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
| _(floor: empty program)_ | _3.193_ | _83.197_ | _**86.390**_ | _59.002_ | _69.378_ |
| `lcg` | 2.863 | 91.293 | **94.156** | 69.377 | 72.878 |
| `packet_classifier` | 2.846 | 91.934 | **94.780** | 70.587 | 69.713 |
| `ring_write` | 3.147 | 94.167 | **97.314** | 72.141 | 71.353 |
| `histogram_bins` | 3.035 | 96.713 | **99.748** | 72.911 | 74.938 |
| `prefix_scan` | 3.025 | 97.419 | **100.444** | 75.543 | 74.351 |
| `binary_search` | 3.234 | 97.116 | **100.350** | 73.005 | 79.577 |
| `sort_window` | 3.275 | 102.211 | **105.486** | 81.213 | 84.275 |
| `bloom_filter` | 3.329 | 101.582 | **104.911** | 79.925 | 79.384 |
| `hash_join` | 5.452 | 219.777 | **225.229** | 124.258 | 116.859 |
| `sieve` | 2.999 | 96.930 | **99.929** | 80.429 | 85.595 |
| `fib` | 2.780 | 91.850 | **94.630** | 69.165 | 67.054 |
| `collatz` | 2.993 | 95.072 | **98.065** | 71.546 | 72.066 |
| `matmul` | 3.253 | 101.756 | **105.009** | 82.887 | 93.633 |
| `json_parse` | 39.762 | 528.269 | **568.031** | 125.830 | 183.766 |
| `nbody` | 4.485 | 112.184 | **116.669** | 98.818 | 95.209 |

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
