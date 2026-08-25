# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-25T07:29:18Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `66e6a4c3db13541fbaa00d459f9cf1be37da42eb` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32821460049 |
| NURL | `v0.51.0-17-g66e6a4c3` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |
| Node | v22.23.2 |
| Python | Python 3.12.3 |

| Setting | Value |
|---|---|
| NURL flags | `nurlc` → LLVM IR; `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` (ThinLTO backend at O3 — the standard `nurl.sh` release pipeline) |
| C flags | `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` — the identical pipeline, so neither column gets a backend the other lacks |
| Rust flags | `rustc -C opt-level=3` — rustc has no prelink/backend split; opt-level 3 is the `cargo build --release` default |
| Node / Python | `node` / `python3`, no flags |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.449_ | _1.516_ | _1.638_ | _23.633_ | _17.322_ |
| `lcg` | **38.898** | 38.921 | 39.185 | 2048.346 | 5274.921 |
| `packet_classifier` | **56.103** | 56.120 | 56.520 | 161.905 | 4361.707 |
| `ring_write` | 42.185 | **42.140** | 42.411 | 66.493 | 6143.012 |
| `histogram_bins` | **39.482** | 40.540 | 39.589 | 66.355 | 6209.727 |
| `prefix_scan` | 21.677 | **21.592** | 21.612 | 64.112 | 4740.066 |
| `binary_search` | **36.148** | 37.972 | 36.928 | 105.059 | 6407.169 |
| `sort_window` | 26.599 | **26.534** | 26.656 | 195.923 | 11695.346 |
| `bloom_filter` | 17.841 | **17.819** | 18.335 | 2823.452 | 7704.686 |
| `hash_join` | **26.790** | 27.819 | 29.152 | 3419.498 | 8374.765 |
| `sieve` | 18.135 | 17.746 | **17.675** | 65.527 | 3185.512 |
| `fib` | **25.046** | 29.697 | 25.210 | 130.071 | 1359.898 |
| `collatz` | 12.280 | **12.170** | 12.341 | 48.082 | 713.414 |
| `matmul` | 33.428 | **33.290** | 33.633 | 75.052 | 3145.014 |
| `json_parse` | 8.860 | **8.581** | 11.599 | 36.132 | 38.303 |
| `nbody` | 25.150 | 39.677 | **23.994** | 100.413 | 3045.433 |

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
| _(floor: empty program)_ | _2.632_ | _90.925_ | _**93.557**_ | _56.568_ | _79.164_ | _55.542_ |
| `lcg` | 2.809 | 91.915 | **94.724** | 57.796 | 87.354 | 60.184 |
| `packet_classifier` | 2.834 | 92.756 | **95.590** | 56.690 | 88.259 | 59.597 |
| `ring_write` | 2.970 | 94.583 | **97.553** | 57.496 | 89.673 | 61.361 |
| `histogram_bins` | 3.045 | 114.343 | **117.388** | 57.781 | 108.932 | 71.183 |
| `prefix_scan` | 3.126 | 97.412 | **100.538** | 57.484 | 95.755 | 66.192 |
| `binary_search` | 3.249 | 102.881 | **106.130** | 57.917 | 91.288 | 67.050 |
| `sort_window` | 3.275 | 103.169 | **106.444** | 58.022 | 101.168 | 71.991 |
| `bloom_filter` | 3.517 | 100.435 | **103.952** | 57.856 | 99.579 | 66.540 |
| `hash_join` | 6.042 | 251.850 | **257.892** | 60.512 | 216.586 | 113.484 |
| `sieve` | 3.180 | 99.515 | **102.695** | 59.203 | 102.773 | 70.929 |
| `fib` | 2.807 | 94.884 | **97.691** | 58.178 | 91.008 | 60.812 |
| `collatz` | 3.014 | 95.449 | **98.463** | 57.310 | 89.834 | 62.039 |
| `matmul` | 3.385 | 98.234 | **101.619** | 57.767 | 103.110 | 83.055 |
| `json_parse` | 51.860 | 428.234 | **480.094** | 107.995 | 160.886 | 167.494 |
| `nbody` | 4.731 | 126.080 | **130.811** | 59.562 | 124.629 | 91.475 |

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
