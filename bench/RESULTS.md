# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T17:15:58Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372444 KiB |
| Commit | `75c2035d6914310148d94eeab5f0f23307e1eb43` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31516326444 |
| NURL | `v0.38.0` |
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
| _(floor: empty program)_ | _1.267_ | _1.294_ | _1.353_ | _19.182_ | _16.199_ |
| `lcg` | 36.092 | **36.034** | 36.050 | 1388.705 | 4066.543 |
| `packet_classifier` | **58.808** | 63.606 | 63.829 | 159.774 | 3341.109 |
| `ring_write` | 41.580 | **40.336** | 42.028 | 62.323 | 4688.499 |
| `histogram_bins` | 38.907 | **37.293** | 37.447 | 66.455 | 4460.497 |
| `prefix_scan` | 20.642 | 21.212 | **20.582** | 62.142 | 3431.774 |
| `binary_search` | 31.377 | **28.805** | 39.843 | 102.513 | 5314.016 |
| `sort_window` | 36.943 | 47.387 | **36.827** | 171.562 | 8471.473 |
| `bloom_filter` | 12.921 | **12.803** | 12.849 | 2228.157 | 5975.277 |
| `hash_join` | **21.276** | 23.330 | 24.386 | 2875.666 | 6491.902 |
| `sieve` | 35.596 | **32.692** | 32.706 | 76.372 | 2437.769 |
| `fib` | 26.113 | 27.293 | **23.137** | 99.682 | 821.203 |
| `collatz` | **13.010** | 14.983 | 14.227 | 53.179 | 508.355 |
| `matmul` | **18.585** | 18.657 | 19.491 | 64.982 | 2412.553 |
| `json_parse` | 8.150 | **7.157** | 9.996 | 31.711 | 29.723 |
| `nbody` | 28.650 | 28.340 | **26.275** | 70.812 | 2131.689 |

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
| _(floor: empty program)_ | _2.095_ | _68.416_ | _**70.511**_ | _50.127_ | _53.075_ |
| `lcg` | 2.370 | 66.321 | **68.691** | 52.550 | 62.071 |
| `packet_classifier` | 2.274 | 71.313 | **73.587** | 56.041 | 61.327 |
| `ring_write` | 2.351 | 66.420 | **68.771** | 53.112 | 61.024 |
| `histogram_bins` | 2.443 | 72.434 | **74.877** | 57.111 | 61.613 |
| `prefix_scan` | 2.514 | 71.430 | **73.944** | 56.174 | 60.593 |
| `binary_search` | 2.800 | 80.099 | **82.899** | 58.295 | 67.161 |
| `sort_window` | 2.942 | 86.661 | **89.603** | 63.987 | 71.195 |
| `bloom_filter` | 2.823 | 78.737 | **81.560** | 57.090 | 69.017 |
| `hash_join` | 5.188 | 170.513 | **175.701** | 96.160 | 93.275 |
| `sieve` | 2.475 | 70.036 | **72.511** | 63.776 | 68.273 |
| `fib` | 2.293 | 75.699 | **77.992** | 129.150 | 60.291 |
| `collatz` | 2.377 | 68.548 | **70.925** | 56.513 | 59.860 |
| `matmul` | 3.513 | 82.968 | **86.481** | 66.757 | 80.323 |
| `json_parse` | 38.409 | 440.990 | **479.399** | 103.413 | 195.305 |
| `nbody` | 4.000 | 87.844 | **91.844** | 73.862 | 78.715 |

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
