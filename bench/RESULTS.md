# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-17T10:57:15Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `18d6a5000c619c846d6f90edd0cee466ba6c1af3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32022192482 |
| NURL | `v0.44.2-10-g18d6a500` |
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
| _(floor: empty program)_ | _1.902_ | _1.957_ | _2.123_ | _26.895_ | _19.832_ |
| `lcg` | **44.573** | 44.641 | 44.800 | 1828.924 | 5493.479 |
| `packet_classifier` | **64.121** | 64.140 | 64.159 | 160.347 | 4701.983 |
| `ring_write` | **48.155** | 48.182 | 48.311 | 76.210 | 6784.801 |
| `histogram_bins` | **45.059** | 45.235 | 45.314 | 77.651 | 6315.049 |
| `prefix_scan` | **24.926** | 25.007 | 25.136 | 75.790 | 4820.522 |
| `binary_search` | **33.834** | 36.344 | 46.442 | 114.456 | 6686.336 |
| `sort_window` | **30.423** | 31.251 | 30.768 | 172.052 | 12212.184 |
| `bloom_filter` | **20.336** | 20.869 | 21.128 | 2832.595 | 7863.988 |
| `hash_join` | **28.150** | 31.472 | 31.896 | 3448.215 | 8253.963 |
| `sieve` | 21.232 | **21.063** | 21.368 | 74.956 | 3483.844 |
| `fib` | **28.442** | 33.857 | 29.959 | 146.494 | 1302.547 |
| `collatz` | **14.128** | 14.186 | 14.224 | 54.494 | 753.125 |
| `matmul` | **45.734** | 46.696 | 45.788 | 86.355 | 3573.878 |
| `json_parse` | **9.346** | 9.384 | 12.719 | 41.822 | 40.579 |
| `nbody` | **27.160** | 46.595 | 44.506 | 99.440 | 3261.356 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc` emits LLVM IR, then `clang`
lowers and links it against `stdlib/runtime.o`. **NURL total** is the
number comparable to the C and Rust columns: a cold compile, measured
against a wiped cache exactly as C and Rust pay their full cost every
time. **NURL rebuild** is the same compile again with the ThinLTO
cache warm — `nurl.sh`'s default on Linux (docs/BUILDING.md → The
ThinLTO cache) — which is what every build after the first costs; C
and Rust have no default equivalent (`ccache`/`sccache` are opt-in
add-ons). The floor row is what each toolchain costs for a program
that does nothing — for NURL that is dominated by the LTO link every
NURL binary pays for, so subtract it to read the marginal cost of the
benchmark itself. Node and Python have no column here: they compile
at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | NURL rebuild | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.262_ | _104.298_ | _**107.560**_ | _67.774_ | _68.648_ | _76.069_ |
| `lcg` | 3.537 | 106.886 | **110.423** | 68.409 | 79.310 | 80.147 |
| `packet_classifier` | 3.582 | 108.587 | **112.169** | 69.115 | 79.203 | 80.329 |
| `ring_write` | 3.774 | 110.890 | **114.664** | 69.872 | 81.826 | 81.703 |
| `histogram_bins` | 3.887 | 130.541 | **134.428** | 69.447 | 82.467 | 84.745 |
| `prefix_scan` | 3.887 | 115.632 | **119.519** | 70.147 | 85.225 | 84.426 |
| `binary_search` | 4.018 | 120.830 | **124.848** | 70.693 | 82.226 | 86.397 |
| `sort_window` | 4.123 | 123.158 | **127.281** | 70.404 | 89.643 | 91.096 |
| `bloom_filter` | 4.291 | 118.476 | **122.767** | 70.557 | 88.435 | 91.565 |
| `hash_join` | 6.821 | 262.268 | **269.089** | 72.554 | 129.491 | 125.468 |
| `sieve` | 3.887 | 114.011 | **117.898** | 69.502 | 90.109 | 91.624 |
| `fib` | 3.591 | 108.383 | **111.974** | 69.053 | 79.363 | 79.491 |
| `collatz` | 3.694 | 109.790 | **113.484** | 69.414 | 79.322 | 79.996 |
| `matmul` | 4.091 | 114.832 | **118.923** | 69.421 | 90.947 | 105.119 |
| `json_parse` | 51.701 | 430.327 | **482.028** | 118.400 | 133.898 | 201.911 |
| `nbody` | 5.404 | 140.699 | **146.103** | 70.681 | 106.669 | 105.264 |

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
