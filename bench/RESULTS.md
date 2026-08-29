# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-29T11:05:05Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `6dae77d01c3a928bef75baecf08272eec95df6e8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33249088630 |
| NURL | `v0.55.0-3-g6dae77d0` |
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
| _(floor: empty program)_ | _1.560_ | _1.515_ | _1.786_ | _23.759_ | _17.682_ |
| `lcg` | **44.007** | 44.014 | 44.330 | 1815.082 | 5458.192 |
| `packet_classifier` | **63.415** | 63.469 | 63.616 | 159.950 | 4748.049 |
| `ring_write` | 47.525 | **47.480** | 47.918 | 74.860 | 6590.914 |
| `histogram_bins` | **44.528** | 44.675 | 44.832 | 75.847 | 6245.125 |
| `prefix_scan` | 24.446 | **24.344** | 24.643 | 72.380 | 4709.517 |
| `binary_search` | 41.382 | **35.590** | 36.506 | 111.261 | 6379.108 |
| `sort_window` | 29.986 | **29.939** | 30.174 | 165.536 | 11270.668 |
| `bloom_filter` | 19.745 | **18.720** | 20.722 | 2710.528 | 8489.563 |
| `hash_join` | **27.569** | 28.484 | 29.977 | 3387.071 | 8219.711 |
| `sieve` | 20.417 | **20.214** | 20.394 | 70.831 | 3386.280 |
| `fib` | **27.884** | 33.122 | 27.991 | 143.284 | 1294.360 |
| `collatz` | 13.705 | **13.670** | 13.893 | 53.142 | 752.561 |
| `matmul` | **45.339** | 46.115 | 46.167 | 83.943 | 3306.306 |
| `json_parse` | **8.688** | 8.896 | 12.134 | 38.899 | 38.625 |
| `nbody` | 26.670 | 44.917 | **26.252** | 97.843 | 3233.956 |

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
| _(floor: empty program)_ | _3.158_ | _105.935_ | _**109.093**_ | _65.386_ | _88.302_ | _67.124_ |
| `lcg` | 3.131 | 115.076 | **118.207** | 66.132 | 99.035 | 74.424 |
| `packet_classifier` | 3.203 | 117.332 | **120.535** | 67.567 | 101.741 | 75.000 |
| `ring_write` | 3.399 | 117.469 | **120.868** | 66.700 | 100.972 | 76.616 |
| `histogram_bins` | 3.363 | 127.271 | **130.634** | 66.454 | 118.308 | 85.877 |
| `prefix_scan` | 3.510 | 118.174 | **121.684** | 66.381 | 109.098 | 80.761 |
| `binary_search` | 3.637 | 121.603 | **125.240** | 67.196 | 104.512 | 82.497 |
| `sort_window` | 3.698 | 120.325 | **124.023** | 66.366 | 112.968 | 89.665 |
| `bloom_filter` | 3.963 | 120.537 | **124.500** | 66.693 | 112.068 | 83.912 |
| `hash_join` | 6.481 | 259.014 | **265.495** | 67.979 | 217.518 | 132.733 |
| `sieve` | 3.489 | 116.317 | **119.806** | 66.376 | 110.987 | 87.749 |
| `fib` | 3.187 | 114.980 | **118.167** | 65.216 | 98.735 | 74.898 |
| `collatz` | 3.331 | 116.551 | **119.882** | 65.150 | 100.412 | 79.291 |
| `matmul` | 3.715 | 117.077 | **120.792** | 66.621 | 113.939 | 101.524 |
| `json_parse` | 52.824 | 424.941 | **477.765** | 116.776 | 166.336 | 186.329 |
| `nbody` | 5.044 | 136.987 | **142.031** | 68.524 | 134.922 | 109.287 |

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
