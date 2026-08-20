# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-20T20:52:33Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `554418bf1c6f1f6661fe4fc37472c497167ab9a7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32416010097 |
| NURL | `v0.47.0-2-g554418bf` |
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
| _(floor: empty program)_ | _1.440_ | _1.417_ | _1.636_ | _24.803_ | _17.240_ |
| `lcg` | 39.101 | **39.005** | 39.236 | 2047.550 | 5484.018 |
| `packet_classifier` | **56.248** | 56.274 | 56.624 | 162.559 | 4444.860 |
| `ring_write` | **42.207** | 42.238 | 42.381 | 66.173 | 6172.431 |
| `histogram_bins` | **39.584** | 40.750 | 39.985 | 67.833 | 6286.368 |
| `prefix_scan` | 21.677 | **21.615** | 21.763 | 67.248 | 4432.426 |
| `binary_search` | **36.230** | 38.154 | 36.899 | 106.881 | 5985.000 |
| `sort_window` | **26.473** | 26.536 | 26.954 | 199.164 | 11263.613 |
| `bloom_filter` | **17.858** | 17.928 | 18.427 | 2843.889 | 7839.137 |
| `hash_join` | **26.926** | 28.071 | 29.372 | 3442.186 | 8365.676 |
| `sieve` | 18.715 | 18.442 | **18.099** | 66.335 | 3556.040 |
| `fib` | **25.168** | 29.790 | 25.256 | 131.114 | 1365.273 |
| `collatz` | 12.271 | **12.215** | 12.390 | 52.124 | 717.605 |
| `matmul` | 33.487 | **33.301** | 33.608 | 76.297 | 3155.210 |
| `json_parse` | 9.012 | **8.679** | 11.764 | 37.103 | 38.169 |
| `nbody` | 25.180 | 39.828 | **24.087** | 101.535 | 3064.910 |

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
| _(floor: empty program)_ | _28.623_ | _118.045_ | _**146.668**_ | _84.546_ | _76.388_ | _54.509_ |
| `lcg` | 2.812 | 93.476 | **96.288** | 57.917 | 88.991 | 60.424 |
| `packet_classifier` | 2.825 | 92.713 | **95.538** | 56.570 | 86.685 | 59.887 |
| `ring_write` | 3.038 | 98.548 | **101.586** | 59.427 | 93.120 | 62.430 |
| `histogram_bins` | 3.137 | 118.544 | **121.681** | 60.220 | 112.575 | 71.332 |
| `prefix_scan` | 3.117 | 101.924 | **105.041** | 59.950 | 98.958 | 66.327 |
| `binary_search` | 3.338 | 104.805 | **108.143** | 60.339 | 95.659 | 67.726 |
| `sort_window` | 3.342 | 109.122 | **112.464** | 60.311 | 106.931 | 73.317 |
| `bloom_filter` | 3.614 | 105.931 | **109.545** | 60.729 | 105.167 | 67.939 |
| `hash_join` | 6.106 | 259.454 | **265.560** | 62.320 | 220.933 | 115.581 |
| `sieve` | 3.216 | 100.267 | **103.483** | 60.223 | 105.116 | 73.371 |
| `fib` | 2.935 | 99.609 | **102.544** | 60.289 | 92.009 | 61.126 |
| `collatz` | 3.023 | 99.717 | **102.740** | 59.997 | 94.816 | 65.306 |
| `matmul` | 3.507 | 102.432 | **105.939** | 60.485 | 107.048 | 86.249 |
| `json_parse` | 53.448 | 441.952 | **495.400** | 113.322 | 166.448 | 171.766 |
| `nbody` | 4.824 | 128.588 | **133.412** | 61.545 | 130.207 | 94.313 |

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
