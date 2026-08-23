# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-23T15:20:47Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `df99c5d3400972df4655d695dc1e37cb145e761e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32648010403 |
| NURL | `v0.49.0-13-gdf99c5d3` |
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
| _(floor: empty program)_ | _1.445_ | _1.446_ | _1.639_ | _22.641_ | _17.124_ |
| `lcg` | **38.933** | 39.066 | 39.199 | 2054.086 | 5366.997 |
| `packet_classifier` | 56.185 | **56.117** | 56.504 | 162.928 | 4345.132 |
| `ring_write` | **42.267** | 42.272 | 42.500 | 67.841 | 6340.238 |
| `histogram_bins` | **39.443** | 40.659 | 39.747 | 67.067 | 6020.835 |
| `prefix_scan` | 21.690 | **21.615** | 21.753 | 65.734 | 4634.558 |
| `binary_search` | **36.197** | 38.324 | 37.229 | 107.406 | 6048.505 |
| `sort_window` | **26.537** | 26.690 | 26.810 | 198.132 | 11475.350 |
| `bloom_filter` | **17.808** | 17.821 | 18.271 | 2833.310 | 8133.881 |
| `hash_join` | **26.913** | 28.022 | 29.434 | 3400.029 | 8227.485 |
| `sieve` | 19.019 | 18.465 | **18.434** | 66.022 | 3308.610 |
| `fib` | **25.156** | 29.868 | 25.381 | 133.621 | 1363.250 |
| `collatz` | **12.222** | 12.228 | 12.375 | 50.660 | 710.808 |
| `matmul` | 33.676 | **33.654** | 33.929 | 78.044 | 3258.575 |
| `json_parse` | 9.150 | **8.777** | 11.723 | 37.845 | 39.805 |
| `nbody` | 25.400 | 39.867 | **24.415** | 102.526 | 3062.607 |

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
| _(floor: empty program)_ | _2.755_ | _95.688_ | _**98.443**_ | _60.719_ | _80.838_ | _64.810_ |
| `lcg` | 2.821 | 95.396 | **98.217** | 58.753 | 90.503 | 60.920 |
| `packet_classifier` | 2.848 | 94.363 | **97.211** | 58.777 | 90.476 | 60.359 |
| `ring_write` | 2.954 | 98.122 | **101.076** | 59.853 | 93.191 | 61.793 |
| `histogram_bins` | 3.097 | 114.798 | **117.895** | 58.541 | 109.684 | 68.935 |
| `prefix_scan` | 3.049 | 99.324 | **102.373** | 58.061 | 95.984 | 63.909 |
| `binary_search` | 3.239 | 103.183 | **106.422** | 58.435 | 92.586 | 67.125 |
| `sort_window` | 3.345 | 105.680 | **109.025** | 58.177 | 102.511 | 71.681 |
| `bloom_filter` | 3.541 | 103.913 | **107.454** | 59.997 | 103.733 | 67.678 |
| `hash_join` | 6.066 | 259.302 | **265.368** | 63.423 | 220.142 | 115.770 |
| `sieve` | 3.138 | 99.821 | **102.959** | 60.234 | 104.112 | 71.894 |
| `fib` | 2.837 | 95.624 | **98.461** | 59.196 | 91.241 | 59.738 |
| `collatz` | 2.969 | 98.871 | **101.840** | 59.631 | 93.085 | 63.276 |
| `matmul` | 3.373 | 101.956 | **105.329** | 59.122 | 106.096 | 84.980 |
| `json_parse` | 53.676 | 440.463 | **494.139** | 112.615 | 163.351 | 169.807 |
| `nbody` | 4.899 | 129.075 | **133.974** | 62.848 | 128.808 | 94.119 |

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
