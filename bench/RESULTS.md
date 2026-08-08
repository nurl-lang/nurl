# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-08T13:44:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `3a3ed7a9a91c96f9bada9a85a71549360fdd412d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31260048449 |
| NURL | `v0.35.1-32-g3a3ed7a9` |
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
| _(floor: empty program)_ | _1.664_ | _1.725_ | _1.842_ | _23.265_ | _17.253_ |
| `lcg` | **39.351** | 39.461 | 39.443 | 1874.532 | 5121.631 |
| `packet_classifier` | **56.534** | 56.615 | 56.794 | 164.040 | 4383.036 |
| `ring_write` | **42.423** | 42.477 | 42.525 | 67.317 | 6424.062 |
| `histogram_bins` | **39.978** | 41.581 | 40.043 | 68.478 | 6190.306 |
| `prefix_scan` | **22.017** | **22.017** | 22.122 | 65.630 | 4621.432 |
| `binary_search` | 40.120 | **38.570** | 43.411 | 108.458 | 6624.811 |
| `sort_window` | 27.405 | 27.609 | **26.904** | 197.487 | 12420.505 |
| `bloom_filter` | **18.058** | 18.211 | 18.472 | 2841.511 | 7759.391 |
| `hash_join` | **27.994** | 30.258 | 30.029 | 3419.061 | 8489.690 |
| `sieve` | 19.178 | 18.491 | **18.472** | 66.528 | 3563.274 |
| `fib` | **25.373** | 29.999 | 28.260 | 132.039 | 1357.559 |
| `collatz` | **12.390** | 12.426 | 12.540 | 49.402 | 714.522 |
| `matmul` | **33.551** | 33.663 | 33.943 | 77.822 | 3426.140 |
| `json_parse` | 42.447 | **8.819** | 11.788 | 36.274 | 37.936 |
| `nbody` | 41.032 | 40.958 | **39.094** | 100.064 | 3128.776 |

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
| _(floor: empty program)_ | _2.956_ | _81.881_ | _**84.837**_ | _59.946_ | _61.626_ |
| `lcg` | 2.771 | 87.486 | **90.257** | 66.819 | 69.880 |
| `packet_classifier` | 2.865 | 88.652 | **91.517** | 68.966 | 68.965 |
| `ring_write` | 3.102 | 90.197 | **93.299** | 70.746 | 71.804 |
| `histogram_bins` | 3.023 | 94.553 | **97.576** | 72.636 | 73.297 |
| `prefix_scan` | 3.068 | 94.987 | **98.055** | 74.528 | 73.321 |
| `binary_search` | 3.220 | 93.659 | **96.879** | 71.442 | 76.606 |
| `sort_window` | 3.247 | 100.008 | **103.255** | 76.794 | 79.537 |
| `bloom_filter` | 3.395 | 98.517 | **101.912** | 76.965 | 76.365 |
| `hash_join` | 5.457 | 212.513 | **217.970** | 121.438 | 112.496 |
| `sieve` | 3.012 | 93.669 | **96.681** | 80.444 | 79.238 |
| `fib` | 2.781 | 86.469 | **89.250** | 66.987 | 68.344 |
| `collatz` | 2.960 | 90.670 | **93.630** | 69.978 | 70.415 |
| `matmul` | 3.262 | 98.071 | **101.333** | 81.832 | 92.397 |
| `json_parse` | 41.299 | 541.805 | **583.104** | 124.859 | 182.585 |
| `nbody` | 4.375 | 109.241 | **113.616** | 97.755 | 92.703 |

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
