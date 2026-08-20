# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-20T17:52:31Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `1ad0697ad374da733823e701f686c22948c1a54c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32399595567 |
| NURL | `v0.47.0` |
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
| _(floor: empty program)_ | _1.472_ | _1.432_ | _1.634_ | _21.863_ | _16.899_ |
| `lcg` | **38.994** | 39.098 | 39.224 | 2052.404 | 5346.070 |
| `packet_classifier` | 56.251 | **56.131** | 56.451 | 162.496 | 4382.124 |
| `ring_write` | 42.063 | **42.051** | 42.208 | 64.926 | 6097.834 |
| `histogram_bins` | **39.486** | 40.612 | 39.708 | 66.945 | 6237.026 |
| `prefix_scan` | 21.646 | **21.612** | 21.632 | 63.742 | 4638.584 |
| `binary_search` | **36.022** | 38.123 | 36.865 | 105.367 | 6258.237 |
| `sort_window` | 26.614 | **26.474** | 26.700 | 197.204 | 11289.387 |
| `bloom_filter` | **17.685** | 17.757 | 18.222 | 2832.236 | 7735.671 |
| `hash_join` | **26.827** | 27.758 | 29.167 | 3393.807 | 8395.581 |
| `sieve` | 20.381 | **19.991** | 20.002 | 67.911 | 3350.921 |
| `fib` | **25.056** | 29.737 | 25.312 | 131.103 | 1353.010 |
| `collatz` | 12.226 | **12.164** | 12.332 | 50.050 | 718.781 |
| `matmul` | 33.640 | **33.448** | 33.817 | 75.159 | 3084.911 |
| `json_parse` | 8.826 | **8.540** | 11.495 | 36.252 | 37.240 |
| `nbody` | 25.073 | 39.704 | **24.002** | 102.289 | 3311.769 |

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
| _(floor: empty program)_ | _2.619_ | _94.456_ | _**97.075**_ | _60.773_ | _82.728_ | _55.069_ |
| `lcg` | 2.812 | 92.121 | **94.933** | 56.463 | 86.914 | 59.593 |
| `packet_classifier` | 2.843 | 91.619 | **94.462** | 56.766 | 87.814 | 59.527 |
| `ring_write` | 2.945 | 95.224 | **98.169** | 58.423 | 90.443 | 60.330 |
| `histogram_bins` | 3.030 | 112.676 | **115.706** | 57.504 | 109.483 | 69.016 |
| `prefix_scan` | 3.091 | 96.571 | **99.662** | 56.393 | 94.342 | 64.401 |
| `binary_search` | 3.213 | 103.024 | **106.237** | 57.815 | 92.325 | 66.049 |
| `sort_window` | 3.298 | 104.566 | **107.864** | 57.097 | 99.368 | 70.195 |
| `bloom_filter` | 3.572 | 99.163 | **102.735** | 57.084 | 98.439 | 65.667 |
| `hash_join` | 6.037 | 251.239 | **257.276** | 59.640 | 216.418 | 117.019 |
| `sieve` | 3.114 | 93.997 | **97.111** | 56.352 | 101.440 | 70.614 |
| `fib` | 2.775 | 89.928 | **92.703** | 56.201 | 86.857 | 58.782 |
| `collatz` | 2.954 | 94.551 | **97.505** | 56.723 | 91.401 | 60.382 |
| `matmul` | 3.346 | 100.031 | **103.377** | 57.150 | 102.882 | 82.147 |
| `json_parse` | 52.896 | 430.499 | **483.395** | 109.517 | 159.568 | 163.309 |
| `nbody` | 4.655 | 124.307 | **128.962** | 59.594 | 127.592 | 91.034 |

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
