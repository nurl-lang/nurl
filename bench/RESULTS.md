# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-29T06:27:01Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373444 KiB |
| Commit | `7820d45570cf5bb357ee2e6c4a0141548b54e3a5` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33238319415 |
| NURL | `v0.54.0-14-g7820d455` |
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
| _(floor: empty program)_ | _1.232_ | _1.190_ | _1.388_ | _18.168_ | _13.548_ |
| `lcg` | 34.153 | **34.107** | 34.318 | 1404.917 | 4116.873 |
| `packet_classifier` | 49.181 | **49.168** | 49.369 | 122.373 | 3525.283 |
| `ring_write` | 37.097 | **36.817** | 37.079 | 56.865 | 5228.428 |
| `histogram_bins` | **34.487** | 34.516 | 34.655 | 56.823 | 4926.754 |
| `prefix_scan` | **18.841** | 18.866 | 19.047 | 54.387 | 3625.345 |
| `binary_search` | 32.049 | **27.633** | 28.227 | 85.568 | 5374.645 |
| `sort_window` | 23.150 | **23.135** | 23.398 | 127.113 | 8706.215 |
| `bloom_filter` | 15.251 | **14.445** | 15.958 | 2086.205 | 6020.005 |
| `hash_join` | **21.356** | 22.161 | 23.280 | 2657.132 | 6309.304 |
| `sieve` | 15.815 | **15.452** | 15.591 | 55.075 | 2792.046 |
| `fib` | **21.588** | 25.592 | 21.725 | 110.355 | 1011.546 |
| `collatz` | 10.574 | **10.534** | 10.708 | 40.907 | 585.714 |
| `matmul` | **34.540** | 35.490 | 35.038 | 64.180 | 2646.802 |
| `json_parse` | **6.701** | 7.005 | 9.395 | 28.822 | 29.137 |
| `nbody` | 20.771 | 34.839 | **20.316** | 74.405 | 2491.319 |

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
| _(floor: empty program)_ | _2.917_ | _91.599_ | _**94.516**_ | _51.969_ | _68.744_ | _52.016_ |
| `lcg` | 7.320 | 96.286 | **103.606** | 56.112 | 76.198 | 59.376 |
| `packet_classifier` | 2.504 | 89.854 | **92.358** | 51.906 | 77.519 | 59.506 |
| `ring_write` | 2.551 | 89.866 | **92.417** | 51.707 | 77.780 | 60.506 |
| `histogram_bins` | 2.638 | 98.243 | **100.881** | 52.226 | 91.091 | 67.689 |
| `prefix_scan` | 2.674 | 91.242 | **93.916** | 52.373 | 81.658 | 63.269 |
| `binary_search` | 2.810 | 91.574 | **94.384** | 51.787 | 79.960 | 64.844 |
| `sort_window` | 2.829 | 92.481 | **95.310** | 52.119 | 87.057 | 67.717 |
| `bloom_filter` | 3.048 | 93.414 | **96.462** | 51.922 | 85.611 | 65.214 |
| `hash_join` | 4.975 | 198.276 | **203.251** | 52.985 | 167.519 | 102.747 |
| `sieve` | 2.714 | 90.306 | **93.020** | 51.930 | 86.191 | 70.663 |
| `fib` | 2.458 | 88.232 | **90.690** | 51.036 | 76.385 | 62.810 |
| `collatz` | 2.639 | 92.190 | **94.829** | 52.213 | 77.867 | 61.187 |
| `matmul` | 2.895 | 90.693 | **93.588** | 52.433 | 87.575 | 79.900 |
| `json_parse` | 41.226 | 324.639 | **365.865** | 90.771 | 127.860 | 145.080 |
| `nbody` | 3.914 | 106.338 | **110.252** | 53.879 | 103.023 | 85.475 |

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
