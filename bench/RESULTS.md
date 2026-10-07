# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-07T09:31:58Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `1342dac562fd89e4a4099f2fd28c43d7d2a8db7d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37600667390 |
| NURL | `v0.70.0-26-g1342dac5` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |
| Node | v22.23.3 |
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
| _(floor: empty program)_ | _1.439_ | _1.407_ | _1.628_ | _22.427_ | _16.895_ |
| `lcg` | 39.061 | **38.974** | 39.248 | 1906.438 | 5057.938 |
| `packet_classifier` | **56.120** | 56.245 | 56.244 | 162.427 | 4355.486 |
| `ring_write` | 42.097 | **42.026** | 42.261 | 65.128 | 8544.083 |
| `histogram_bins` | **39.415** | 40.553 | 40.728 | 65.145 | 6292.353 |
| `prefix_scan` | 21.680 | **21.581** | 21.829 | 63.943 | 4593.431 |
| `binary_search` | 39.355 | **37.961** | 40.852 | 106.325 | 6298.005 |
| `sort_window` | 26.590 | **26.509** | 26.665 | 196.747 | 11706.434 |
| `bloom_filter` | **15.292** | 17.733 | 18.248 | 2830.938 | 7715.929 |
| `hash_join` | **26.434** | 27.817 | 29.141 | 3515.237 | 8381.311 |
| `sieve` | 20.084 | 20.050 | **19.935** | 65.502 | 3230.889 |
| `fib` | **25.236** | 29.863 | 29.997 | 131.457 | 1352.795 |
| `collatz` | 12.210 | **12.195** | 12.401 | 47.547 | 745.926 |
| `matmul` | 33.336 | **33.072** | 33.414 | 74.398 | 3135.170 |
| `json_parse` | 8.892 | **8.547** | 11.739 | 34.988 | 37.966 |
| `nbody` | **25.066** | 39.617 | 25.136 | 102.139 | 3208.430 |

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
| _(floor: empty program)_ | _3.378_ | _97.716_ | _**101.094**_ | _57.941_ | _77.278_ | _52.387_ |
| `lcg` | 3.539 | 109.943 | **113.482** | 59.771 | 88.329 | 56.642 |
| `packet_classifier` | 3.673 | 110.295 | **113.968** | 59.499 | 88.251 | 57.140 |
| `ring_write` | 3.854 | 111.965 | **115.819** | 60.363 | 91.966 | 58.338 |
| `histogram_bins` | 4.045 | 119.101 | **123.146** | 59.890 | 107.246 | 64.717 |
| `prefix_scan` | 4.097 | 112.616 | **116.713** | 59.584 | 94.552 | 61.601 |
| `binary_search` | 4.283 | 112.048 | **116.331** | 60.217 | 90.808 | 62.735 |
| `sort_window` | 4.406 | 114.479 | **118.885** | 59.979 | 101.748 | 66.892 |
| `bloom_filter` | 4.934 | 115.130 | **120.064** | 60.739 | 99.863 | 63.891 |
| `hash_join` | 8.761 | 262.166 | **270.927** | 64.599 | 216.215 | 108.195 |
| `sieve` | 4.014 | 111.438 | **115.452** | 59.863 | 101.152 | 66.757 |
| `fib` | 3.733 | 111.667 | **115.400** | 61.557 | 90.810 | 56.226 |
| `collatz` | 3.908 | 113.089 | **116.997** | 59.881 | 89.778 | 58.509 |
| `matmul` | 4.708 | 112.196 | **116.904** | 60.401 | 103.336 | 76.483 |
| `json_parse` | 46.381 | 459.328 | **505.709** | 103.019 | 158.119 | 154.290 |
| `nbody` | 6.873 | 132.560 | **139.433** | 63.322 | 126.603 | 92.682 |

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
