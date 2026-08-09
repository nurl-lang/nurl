# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-09T19:05:43Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373460 KiB |
| Commit | `f710a46e9d2e014d790accfce0f4bf11905891a0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31330523792 |
| NURL | `v0.36.0-37-gf710a46e` |
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
| _(floor: empty program)_ | _1.795_ | _1.878_ | _2.027_ | _27.585_ | _18.859_ |
| `lcg` | **44.445** | 44.502 | 44.687 | 1837.584 | 5367.929 |
| `packet_classifier` | **63.816** | 63.906 | 64.069 | 160.258 | 4503.442 |
| `ring_write` | **48.086** | 48.128 | 48.261 | 74.807 | 6528.143 |
| `histogram_bins` | **44.910** | 45.087 | 45.208 | 76.071 | 6239.252 |
| `prefix_scan` | **24.764** | 24.920 | 25.040 | 75.444 | 4715.699 |
| `binary_search` | **36.021** | 36.136 | 46.448 | 113.058 | 6687.111 |
| `sort_window` | 31.104 | 31.221 | **30.652** | 166.513 | 13056.808 |
| `bloom_filter` | **20.169** | 20.794 | 21.123 | 2770.606 | 7781.250 |
| `hash_join` | **29.637** | 31.264 | 31.572 | 3531.173 | 8181.138 |
| `sieve` | 20.745 | **20.715** | 21.015 | 72.478 | 3613.522 |
| `fib` | **28.311** | 33.743 | 29.796 | 144.542 | 1293.661 |
| `collatz` | **13.975** | 14.138 | 14.140 | 54.569 | 756.342 |
| `matmul` | **45.461** | 47.046 | 48.529 | 84.897 | 3487.655 |
| `json_parse` | 47.275 | **9.308** | 12.624 | 42.553 | 40.353 |
| `nbody` | 46.678 | 46.612 | **44.528** | 101.387 | 3205.315 |

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
| _(floor: empty program)_ | _3.011_ | _94.837_ | _**97.848**_ | _71.721_ | _68.207_ |
| `lcg` | 3.252 | 100.543 | **103.795** | 78.701 | 75.590 |
| `packet_classifier` | 3.233 | 100.768 | **104.001** | 78.526 | 76.197 |
| `ring_write` | 3.339 | 102.025 | **105.364** | 77.977 | 78.418 |
| `histogram_bins` | 3.464 | 106.002 | **109.466** | 81.793 | 79.872 |
| `prefix_scan` | 3.500 | 108.507 | **112.007** | 83.613 | 80.051 |
| `binary_search` | 3.576 | 105.430 | **109.006** | 81.599 | 82.016 |
| `sort_window` | 3.724 | 115.785 | **119.509** | 87.185 | 87.715 |
| `bloom_filter` | 3.892 | 109.953 | **113.845** | 87.435 | 82.828 |
| `hash_join` | 6.018 | 216.101 | **222.119** | 127.657 | 119.791 |
| `sieve` | 3.449 | 113.064 | **116.513** | 88.074 | 86.701 |
| `fib` | 3.186 | 100.872 | **104.058** | 81.527 | 74.451 |
| `collatz` | 3.365 | 104.457 | **107.822** | 79.305 | 79.387 |
| `matmul` | 3.709 | 111.542 | **115.251** | 90.862 | 105.906 |
| `json_parse` | 42.422 | 534.399 | **576.821** | 132.172 | 197.398 |
| `nbody` | 4.855 | 124.158 | **129.013** | 107.423 | 105.194 |

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
