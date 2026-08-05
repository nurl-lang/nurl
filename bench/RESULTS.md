# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-05T23:17:12Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `9cf261c51fe01af2a2b56075fd4a0c374673167a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31055550978 |
| NURL | `v0.33.0-44-g9cf261c5` |
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
| _(floor: empty program)_ | _1.666_ | _1.721_ | _1.858_ | _22.896_ | _17.313_ |
| `lcg` | 39.384 | **39.339** | 39.435 | 1876.508 | 5113.377 |
| `packet_classifier` | **56.295** | 56.420 | 56.535 | 162.062 | 4472.870 |
| `ring_write` | 42.358 | **42.324** | 42.427 | 66.276 | 6382.892 |
| `histogram_bins` | **39.595** | 41.372 | 39.833 | 65.683 | 5975.345 |
| `prefix_scan` | **21.818** | 21.890 | 21.993 | 64.730 | 4416.894 |
| `binary_search` | 39.962 | **38.498** | 43.178 | 105.022 | 5900.816 |
| `sort_window` | 27.295 | 27.367 | **26.857** | 198.276 | 11188.225 |
| `bloom_filter` | **17.994** | 18.198 | 18.510 | 2819.277 | 7580.445 |
| `hash_join` | **28.178** | 30.112 | 29.907 | 3448.150 | 8276.538 |
| `sieve` | 18.511 | **18.152** | 18.287 | 65.405 | 3500.279 |
| `fib` | **25.287** | 30.071 | 28.406 | 131.960 | 1369.082 |
| `collatz` | **12.423** | 12.505 | 12.608 | 50.768 | 712.057 |
| `matmul` | **33.536** | 33.654 | 33.717 | 76.767 | 3158.675 |
| `json_parse` | **8.641** | 8.761 | 11.781 | 35.388 | 37.227 |
| `nbody` | 40.835 | 40.926 | **39.091** | 100.544 | 3093.322 |

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
| _(floor: empty program)_ | _2.631_ | _80.224_ | _**82.855**_ | _58.242_ | _60.053_ |
| `lcg` | 2.743 | 85.550 | **88.293** | 66.124 | 67.270 |
| `packet_classifier` | 2.772 | 85.258 | **88.030** | 66.301 | 70.287 |
| `ring_write` | 2.896 | 86.854 | **89.750** | 66.830 | 67.373 |
| `histogram_bins` | 2.950 | 94.509 | **97.459** | 72.491 | 71.486 |
| `prefix_scan` | 2.961 | 92.581 | **95.542** | 71.961 | 72.886 |
| `binary_search` | 3.085 | 89.345 | **92.430** | 67.772 | 73.908 |
| `sort_window` | 3.130 | 96.985 | **100.115** | 73.929 | 77.988 |
| `bloom_filter` | 3.268 | 95.816 | **99.084** | 76.265 | 73.568 |
| `hash_join` | 5.377 | 213.751 | **219.128** | 121.142 | 111.479 |
| `sieve` | 3.002 | 92.377 | **95.379** | 77.684 | 79.097 |
| `fib` | 2.700 | 82.736 | **85.436** | 65.287 | 66.578 |
| `collatz` | 2.896 | 87.960 | **90.856** | 66.386 | 69.644 |
| `matmul` | 3.164 | 96.492 | **99.656** | 80.046 | 90.461 |
| `json_parse` | 40.157 | 514.850 | **555.007** | 123.185 | 176.283 |
| `nbody` | 4.247 | 109.338 | **113.585** | 97.137 | 92.871 |

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
