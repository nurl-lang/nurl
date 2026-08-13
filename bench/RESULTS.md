# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-13T09:48:52Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `4a4da90961ecd252f721c373fa2063366389cbb4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31687945543 |
| NURL | `v0.39.0-35-g4a4da909` |
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
| _(floor: empty program)_ | _1.662_ | _1.733_ | _1.843_ | _21.968_ | _16.878_ |
| `lcg` | 39.492 | **39.481** | 39.557 | 1875.202 | 5235.791 |
| `packet_classifier` | **56.292** | 56.432 | 56.537 | 161.415 | 4778.533 |
| `ring_write` | **42.416** | 42.438 | 42.551 | 65.137 | 6505.114 |
| `histogram_bins` | **39.656** | 41.431 | 39.794 | 65.618 | 6070.312 |
| `prefix_scan` | **21.851** | 21.956 | 22.046 | 65.837 | 4618.896 |
| `binary_search` | **36.316** | 38.531 | 43.215 | 106.018 | 7756.208 |
| `sort_window` | **26.846** | 27.545 | 26.995 | 195.649 | 11568.234 |
| `bloom_filter` | **18.047** | 18.276 | 18.512 | 2837.874 | 7640.393 |
| `hash_join` | **27.177** | 30.372 | 30.039 | 3483.813 | 8212.032 |
| `sieve` | 20.509 | **20.099** | 20.424 | 67.453 | 3280.263 |
| `fib` | **25.347** | 30.006 | 28.306 | 131.574 | 1341.484 |
| `collatz` | 12.481 | **12.473** | 12.621 | 50.574 | 715.478 |
| `matmul` | **33.680** | 33.693 | 33.867 | 77.108 | 3075.938 |
| `json_parse` | 8.968 | **8.858** | 11.853 | 35.852 | 37.253 |
| `nbody` | **25.316** | 40.988 | 39.149 | 99.416 | 3095.571 |

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
| _(floor: empty program)_ | _2.786_ | _89.304_ | _**92.090**_ | _58.565_ | _55.880_ | _59.770_ |
| `lcg` | 2.860 | 90.320 | **93.180** | 57.409 | 65.505 | 69.819 |
| `packet_classifier` | 2.991 | 92.141 | **95.132** | 58.484 | 67.831 | 70.333 |
| `ring_write` | 3.042 | 91.385 | **94.427** | 57.685 | 67.113 | 70.032 |
| `histogram_bins` | 3.095 | 111.624 | **114.719** | 57.830 | 68.771 | 72.073 |
| `prefix_scan` | 3.148 | 96.308 | **99.456** | 57.569 | 70.723 | 72.709 |
| `binary_search` | 3.321 | 101.347 | **104.668** | 58.228 | 68.981 | 74.804 |
| `sort_window` | 3.350 | 103.708 | **107.058** | 58.245 | 74.989 | 79.426 |
| `bloom_filter` | 3.595 | 100.923 | **104.518** | 58.489 | 75.228 | 76.673 |
| `hash_join` | 5.911 | 254.756 | **260.667** | 61.455 | 120.420 | 111.309 |
| `sieve` | 3.179 | 97.449 | **100.628** | 58.528 | 79.742 | 79.890 |
| `fib` | 2.946 | 91.594 | **94.540** | 58.529 | 67.619 | 68.175 |
| `collatz` | 3.112 | 96.038 | **99.150** | 59.041 | 69.691 | 71.579 |
| `matmul` | 3.430 | 101.232 | **104.662** | 59.797 | 81.242 | 100.336 |
| `json_parse` | 47.600 | 432.047 | **479.647** | 105.275 | 124.678 | 178.382 |
| `nbody` | 4.646 | 125.113 | **129.759** | 61.072 | 97.078 | 96.288 |

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
