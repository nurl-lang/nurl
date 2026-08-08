# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-08T16:35:49Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `020202cdda4e7fc1a5cdc64d7d1a822312a21721` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31267142956 |
| NURL | `v0.36.0` |
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
| _(floor: empty program)_ | _1.510_ | _1.496_ | _1.599_ | _23.355_ | _16.633_ |
| `lcg` | 42.566 | 42.501 | **42.389** | 1559.517 | 4505.255 |
| `packet_classifier` | **67.990** | 74.435 | 73.382 | 178.131 | 3906.361 |
| `ring_write` | 46.703 | **45.905** | 46.845 | 71.419 | 5609.354 |
| `histogram_bins` | **43.528** | 43.718 | 43.876 | 72.837 | 4977.040 |
| `prefix_scan` | **23.516** | 24.122 | 24.031 | 71.082 | 3868.974 |
| `binary_search` | 36.190 | **33.212** | 46.709 | 119.197 | 5256.220 |
| `sort_window` | 43.518 | 54.531 | **42.863** | 190.486 | 9813.193 |
| `bloom_filter` | 15.409 | **15.268** | 15.686 | 2495.255 | 6878.274 |
| `hash_join` | **25.654** | 27.541 | 28.200 | 3117.979 | 7315.885 |
| `sieve` | 37.765 | 37.246 | **36.068** | 86.681 | 2982.276 |
| `fib` | 30.752 | 31.926 | **27.717** | 118.725 | 935.602 |
| `collatz` | **16.118** | 16.628 | 16.309 | 65.630 | 588.903 |
| `matmul` | **21.933** | 21.963 | 22.181 | 78.696 | 2518.808 |
| `json_parse` | 38.925 | **8.443** | 10.427 | 34.957 | 36.834 |
| `nbody` | 34.383 | 34.476 | **31.903** | 88.371 | 2223.361 |

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
| _(floor: empty program)_ | _2.758_ | _82.202_ | _**84.960**_ | _57.592_ | _61.358_ |
| `lcg` | 2.612 | 76.523 | **79.135** | 59.498 | 69.813 |
| `packet_classifier` | 2.971 | 86.578 | **89.549** | 68.099 | 74.606 |
| `ring_write` | 2.942 | 85.666 | **88.608** | 67.305 | 74.551 |
| `histogram_bins` | 2.993 | 88.949 | **91.942** | 69.375 | 74.966 |
| `prefix_scan` | 3.162 | 91.930 | **95.092** | 72.479 | 76.074 |
| `binary_search` | 3.175 | 91.091 | **94.266** | 70.199 | 85.307 |
| `sort_window` | 3.250 | 98.130 | **101.380** | 75.518 | 83.065 |
| `bloom_filter` | 3.616 | 98.643 | **102.259** | 74.950 | 88.111 |
| `hash_join` | 5.110 | 184.062 | **189.172** | 104.042 | 108.064 |
| `sieve` | 2.997 | 83.762 | **86.759** | 67.142 | 82.093 |
| `fib` | 2.831 | 83.525 | **86.356** | 63.666 | 69.464 |
| `collatz` | 3.071 | 88.618 | **91.689** | 67.104 | 76.854 |
| `matmul` | 3.395 | 96.142 | **99.537** | 77.287 | 99.461 |
| `json_parse` | 40.908 | 496.256 | **537.164** | 116.168 | 195.270 |
| `nbody` | 4.171 | 106.256 | **110.427** | 95.071 | 103.343 |

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
