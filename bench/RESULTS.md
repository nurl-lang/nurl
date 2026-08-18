# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-18T04:26:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `ef203715ccd8df625dd8a9b45c483fdda3b1b97a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32098872745 |
| NURL | `v0.44.2-22-gef203715` |
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
| _(floor: empty program)_ | _1.702_ | _1.745_ | _1.935_ | _23.907_ | _17.050_ |
| `lcg` | **39.398** | 39.414 | 39.589 | 2052.445 | 5145.019 |
| `packet_classifier` | **56.568** | 56.852 | 56.748 | 162.829 | 4396.859 |
| `ring_write` | **42.518** | 42.533 | 42.569 | 66.107 | 6436.127 |
| `histogram_bins` | **39.783** | 41.440 | 39.879 | 66.233 | 6110.375 |
| `prefix_scan` | **21.893** | 21.936 | 22.129 | 65.010 | 4597.101 |
| `binary_search` | **36.561** | 38.538 | 43.336 | 106.105 | 5998.713 |
| `sort_window` | **26.705** | 27.355 | 26.993 | 197.335 | 11856.971 |
| `bloom_filter` | **18.006** | 18.303 | 18.468 | 2871.081 | 7773.875 |
| `hash_join` | **27.999** | 30.292 | 30.149 | 3401.742 | 8169.767 |
| `sieve` | 18.482 | **18.085** | 18.285 | 65.438 | 3191.289 |
| `fib` | **25.320** | 29.936 | 28.318 | 130.952 | 1362.069 |
| `collatz` | **12.439** | 12.503 | 12.636 | 51.092 | 715.169 |
| `matmul` | 33.705 | **33.676** | 33.894 | 77.074 | 3392.473 |
| `json_parse` | 9.153 | **8.912** | 11.750 | 36.316 | 37.438 |
| `nbody` | **25.524** | 40.897 | 38.958 | 99.890 | 3053.438 |

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
| _(floor: empty program)_ | _2.887_ | _90.061_ | _**92.948**_ | _58.930_ | _56.862_ | _61.079_ |
| `lcg` | 3.051 | 91.408 | **94.459** | 57.726 | 66.301 | 68.645 |
| `packet_classifier` | 3.092 | 93.156 | **96.248** | 58.308 | 69.645 | 70.151 |
| `ring_write` | 3.179 | 95.109 | **98.288** | 58.649 | 68.413 | 73.120 |
| `histogram_bins` | 3.264 | 112.880 | **116.144** | 58.240 | 70.634 | 73.006 |
| `prefix_scan` | 3.245 | 98.336 | **101.581** | 58.387 | 73.833 | 73.424 |
| `binary_search` | 3.443 | 103.593 | **107.036** | 58.383 | 69.468 | 79.547 |
| `sort_window` | 3.455 | 105.032 | **108.487** | 58.779 | 75.669 | 78.909 |
| `bloom_filter` | 3.702 | 101.811 | **105.513** | 59.123 | 77.657 | 75.705 |
| `hash_join` | 6.253 | 254.862 | **261.115** | 60.740 | 119.101 | 110.185 |
| `sieve` | 3.348 | 97.085 | **100.433** | 58.041 | 78.418 | 78.638 |
| `fib` | 3.034 | 91.218 | **94.252** | 57.899 | 65.993 | 67.126 |
| `collatz` | 3.205 | 94.029 | **97.234** | 58.839 | 68.020 | 69.993 |
| `matmul` | 3.529 | 102.810 | **106.339** | 58.733 | 80.042 | 95.656 |
| `json_parse` | 51.590 | 428.866 | **480.456** | 108.447 | 123.099 | 177.794 |
| `nbody` | 4.942 | 123.947 | **128.889** | 60.151 | 97.047 | 93.550 |

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
