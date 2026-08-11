# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-11T23:23:50Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `8caaa95656e164651a483bc7f0023d010fcc17d9` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31546046276 |
| NURL | `v0.38.0-25-g8caaa956` |
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
| _(floor: empty program)_ | _1.279_ | _1.339_ | _1.426_ | _21.187_ | _13.947_ |
| `lcg` | 37.211 | **35.767** | 36.703 | 1432.373 | 3898.123 |
| `packet_classifier` | **56.332** | 62.770 | 60.244 | 156.879 | 3217.591 |
| `ring_write` | 39.857 | **38.670** | 40.749 | 58.259 | 4622.148 |
| `histogram_bins` | 37.345 | **36.624** | 37.481 | 59.532 | 4284.299 |
| `prefix_scan` | **19.367** | 21.027 | 20.307 | 58.262 | 3242.191 |
| `binary_search` | 31.072 | **27.829** | 39.380 | 99.542 | 4713.725 |
| `sort_window` | 37.557 | 45.243 | **35.361** | 162.716 | 9008.785 |
| `bloom_filter` | **12.611** | 12.661 | 12.870 | 2195.677 | 6064.550 |
| `hash_join` | **22.576** | 24.050 | 23.665 | 2734.014 | 6502.779 |
| `sieve` | 33.844 | **32.467** | 33.264 | 75.931 | 2366.564 |
| `fib` | 25.134 | 26.465 | **24.676** | 100.647 | 810.182 |
| `collatz` | **13.737** | 13.975 | 14.595 | 54.257 | 507.766 |
| `matmul` | 17.937 | **17.930** | 18.257 | 64.691 | 2365.270 |
| `json_parse` | **6.716** | 6.773 | 8.435 | 30.398 | 29.834 |
| `nbody` | 28.930 | 30.777 | **26.144** | 72.251 | 1937.849 |

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
| _(floor: empty program)_ | _2.122_ | _76.060_ | _**78.182**_ | _45.739_ | _55.733_ |
| `lcg` | 2.292 | 68.326 | **70.618** | 86.353 | 61.207 |
| `packet_classifier` | 2.329 | 71.751 | **74.080** | 49.366 | 59.296 |
| `ring_write` | 2.764 | 69.862 | **72.626** | 50.881 | 60.023 |
| `histogram_bins` | 2.445 | 69.516 | **71.961** | 51.768 | 65.937 |
| `prefix_scan` | 2.505 | 71.586 | **74.091** | 54.240 | 62.374 |
| `binary_search` | 2.686 | 74.292 | **76.978** | 51.012 | 65.264 |
| `sort_window` | 2.643 | 78.639 | **81.282** | 56.672 | 67.738 |
| `bloom_filter` | 2.826 | 80.639 | **83.465** | 56.420 | 64.310 |
| `hash_join` | 4.997 | 162.824 | **167.821** | 99.687 | 95.953 |
| `sieve` | 2.489 | 72.915 | **75.404** | 61.363 | 69.870 |
| `fib` | 2.259 | 68.314 | **70.573** | 49.604 | 59.343 |
| `collatz` | 2.509 | 71.164 | **73.673** | 50.134 | 60.774 |
| `matmul` | 2.743 | 71.143 | **73.886** | 58.978 | 82.013 |
| `json_parse` | 37.919 | 419.180 | **457.099** | 94.037 | 170.937 |
| `nbody` | 3.578 | 84.390 | **87.968** | 71.788 | 81.750 |

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
