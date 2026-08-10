# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-10T21:23:34Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `d5f791bcac96cc66574a46b8b60769685c36da56` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31433291286 |
| NURL | `v0.36.0-78-gd5f791bc` |
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
| _(floor: empty program)_ | _1.340_ | _1.384_ | _1.463_ | _20.225_ | _15.289_ |
| `lcg` | **37.621** | 37.888 | 38.647 | 1466.564 | 4266.957 |
| `packet_classifier` | **62.764** | 67.295 | 65.517 | 161.438 | 3441.294 |
| `ring_write` | 42.187 | **40.788** | 42.018 | 61.606 | 5116.594 |
| `histogram_bins` | 40.228 | 40.294 | **40.189** | 64.624 | 4638.823 |
| `prefix_scan` | 21.684 | 22.098 | **21.364** | 62.088 | 3460.038 |
| `binary_search` | 33.287 | **30.200** | 41.449 | 104.647 | 5100.258 |
| `sort_window` | 40.185 | 50.509 | **39.613** | 175.420 | 10541.593 |
| `bloom_filter` | 13.942 | 13.676 | **13.628** | 2260.727 | 6426.126 |
| `hash_join` | **23.245** | 25.535 | 26.586 | 2870.665 | 6693.765 |
| `sieve` | 34.538 | **33.845** | 34.028 | 81.742 | 2716.483 |
| `fib` | 29.080 | 28.813 | **25.099** | 105.341 | 852.200 |
| `collatz` | **14.250** | 14.949 | 15.434 | 55.904 | 536.516 |
| `matmul` | 19.481 | 19.593 | **18.853** | 67.016 | 2389.013 |
| `json_parse` | 35.074 | **7.471** | 9.199 | 30.160 | 30.911 |
| `nbody` | 31.867 | 32.194 | **28.768** | 78.362 | 2063.809 |

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
| _(floor: empty program)_ | _2.275_ | _63.273_ | _**65.548**_ | _45.489_ | _56.346_ |
| `lcg` | 2.405 | 69.871 | **72.276** | 48.751 | 60.279 |
| `packet_classifier` | 2.488 | 72.692 | **75.180** | 60.076 | 59.129 |
| `ring_write` | 2.523 | 66.371 | **68.894** | 53.672 | 62.363 |
| `histogram_bins` | 2.634 | 71.706 | **74.340** | 52.752 | 63.721 |
| `prefix_scan` | 2.582 | 73.918 | **76.500** | 55.794 | 64.316 |
| `binary_search` | 2.768 | 70.655 | **73.423** | 51.566 | 66.669 |
| `sort_window` | 2.742 | 80.661 | **83.403** | 60.122 | 72.541 |
| `bloom_filter` | 3.053 | 80.371 | **83.424** | 59.180 | 65.712 |
| `hash_join` | 4.961 | 167.707 | **172.668** | 95.690 | 102.496 |
| `sieve` | 2.596 | 73.209 | **75.805** | 58.648 | 70.754 |
| `fib` | 2.360 | 66.004 | **68.364** | 49.262 | 58.689 |
| `collatz` | 2.475 | 71.082 | **73.557** | 50.597 | 61.767 |
| `matmul` | 2.655 | 74.759 | **77.414** | 61.472 | 83.130 |
| `json_parse` | 39.676 | 458.054 | **497.730** | 99.220 | 175.776 |
| `nbody` | 3.737 | 89.382 | **93.119** | 77.723 | 85.158 |

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
