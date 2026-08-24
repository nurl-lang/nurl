# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-24T10:39:58Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `24ed72a33d35716118872a3f9bf4a881a75329b1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32717515707 |
| NURL | `v0.50.0-9-g24ed72a3` |
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
| _(floor: empty program)_ | _1.426_ | _1.453_ | _1.639_ | _23.227_ | _16.904_ |
| `lcg` | 39.075 | **39.038** | 39.160 | 2048.383 | 5152.203 |
| `packet_classifier` | 56.240 | **56.120** | 56.417 | 162.394 | 4598.570 |
| `ring_write` | 42.167 | **42.111** | 42.427 | 65.838 | 6052.232 |
| `histogram_bins` | **39.513** | 40.597 | 39.596 | 67.129 | 6298.136 |
| `prefix_scan` | 21.720 | **21.689** | 21.708 | 63.857 | 4511.674 |
| `binary_search` | **36.129** | 38.088 | 36.912 | 106.903 | 6570.639 |
| `sort_window` | 26.530 | **26.522** | 26.710 | 197.027 | 11333.687 |
| `bloom_filter` | **17.802** | 17.861 | 18.339 | 2887.380 | 7758.090 |
| `hash_join` | **26.909** | 27.846 | 29.217 | 3441.866 | 8311.891 |
| `sieve` | 20.288 | **19.885** | 20.367 | 67.977 | 3353.563 |
| `fib` | **24.990** | 29.778 | 25.254 | 131.202 | 1352.715 |
| `collatz` | 12.424 | **12.194** | 12.417 | 50.895 | 721.746 |
| `matmul` | 33.555 | **33.298** | 33.509 | 76.545 | 3358.165 |
| `json_parse` | 8.920 | **8.522** | 11.562 | 35.807 | 37.552 |
| `nbody` | 25.175 | 39.746 | **24.185** | 101.512 | 3057.828 |

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
| _(floor: empty program)_ | _2.792_ | _92.923_ | _**95.715**_ | _58.954_ | _77.176_ | _54.481_ |
| `lcg` | 2.807 | 94.276 | **97.083** | 59.313 | 89.126 | 59.799 |
| `packet_classifier` | 2.840 | 94.662 | **97.502** | 58.679 | 89.381 | 58.896 |
| `ring_write` | 2.947 | 95.513 | **98.460** | 58.346 | 90.941 | 60.841 |
| `histogram_bins` | 3.014 | 115.288 | **118.302** | 57.878 | 105.343 | 68.809 |
| `prefix_scan` | 3.080 | 97.631 | **100.711** | 57.794 | 94.621 | 63.787 |
| `binary_search` | 3.217 | 103.331 | **106.548** | 59.087 | 92.140 | 66.407 |
| `sort_window` | 3.317 | 104.176 | **107.493** | 58.217 | 99.939 | 70.479 |
| `bloom_filter` | 3.522 | 102.026 | **105.548** | 59.323 | 100.290 | 67.284 |
| `hash_join` | 6.002 | 254.693 | **260.695** | 61.283 | 217.404 | 114.787 |
| `sieve` | 3.097 | 98.234 | **101.331** | 59.058 | 101.713 | 71.701 |
| `fib` | 2.823 | 94.631 | **97.454** | 58.877 | 88.565 | 58.673 |
| `collatz` | 2.967 | 97.264 | **100.231** | 58.488 | 91.585 | 62.910 |
| `matmul` | 3.353 | 100.112 | **103.465** | 58.873 | 105.365 | 83.874 |
| `json_parse` | 52.605 | 430.181 | **482.786** | 110.364 | 163.005 | 165.591 |
| `nbody` | 4.691 | 124.850 | **129.541** | 60.538 | 126.451 | 92.912 |

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
