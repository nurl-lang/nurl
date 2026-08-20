# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-20T15:45:09Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377684 KiB |
| Commit | `f972ccb91e5670b6351b38b507b28eaad9852917` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32387545933 |
| NURL | `v0.46.0-13-gf972ccb9` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
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
| _(floor: empty program)_ | _1.412_ | _1.410_ | _1.611_ | _22.933_ | _16.722_ |
| `lcg` | 38.904 | **38.887** | 39.172 | 2052.356 | 5049.066 |
| `packet_classifier` | 56.294 | **56.187** | 56.401 | 161.912 | 4757.438 |
| `ring_write` | **42.211** | 42.234 | 42.472 | 66.035 | 6207.343 |
| `histogram_bins` | **39.558** | 40.692 | 39.792 | 67.954 | 6165.729 |
| `prefix_scan` | 21.759 | **21.756** | 21.984 | 65.940 | 4684.213 |
| `binary_search` | **36.269** | 38.297 | 40.008 | 106.869 | 6076.017 |
| `sort_window` | **26.581** | 26.591 | 26.831 | 198.103 | 11501.202 |
| `bloom_filter` | **17.732** | 17.807 | 18.303 | 2841.920 | 7404.718 |
| `hash_join` | **26.954** | 28.044 | 29.269 | 3418.220 | 8289.541 |
| `sieve` | 20.186 | **19.822** | 20.161 | 66.378 | 3233.793 |
| `fib` | **25.213** | 29.994 | 28.147 | 131.789 | 1355.285 |
| `collatz` | 12.220 | **12.106** | 12.292 | 49.337 | 721.473 |
| `matmul` | **33.407** | 33.558 | 33.697 | 76.834 | 3320.613 |
| `json_parse` | 8.857 | **8.518** | 11.691 | 35.864 | 38.261 |
| `nbody` | 25.292 | 39.760 | **24.051** | 100.388 | 3029.569 |

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
| _(floor: empty program)_ | _2.599_ | _91.210_ | _**93.809**_ | _58.195_ | _79.858_ | _59.724_ |
| `lcg` | 2.727 | 91.438 | **94.165** | 56.600 | 86.733 | 68.312 |
| `packet_classifier` | 2.847 | 95.937 | **98.784** | 58.019 | 90.387 | 69.101 |
| `ring_write` | 2.914 | 95.886 | **98.800** | 58.641 | 91.399 | 68.661 |
| `histogram_bins` | 3.022 | 115.069 | **118.091** | 59.342 | 108.883 | 77.003 |
| `prefix_scan` | 3.071 | 100.974 | **104.045** | 59.984 | 100.042 | 74.080 |
| `binary_search` | 3.192 | 104.116 | **107.308** | 59.153 | 97.880 | 81.563 |
| `sort_window` | 3.262 | 105.255 | **108.517** | 59.131 | 103.028 | 80.094 |
| `bloom_filter` | 3.519 | 102.835 | **106.354** | 59.341 | 102.601 | 75.263 |
| `hash_join` | 6.008 | 257.103 | **263.111** | 61.876 | 218.093 | 121.794 |
| `sieve` | 3.111 | 98.867 | **101.978** | 59.118 | 101.954 | 79.416 |
| `fib` | 2.834 | 95.001 | **97.835** | 58.542 | 89.707 | 67.212 |
| `collatz` | 2.994 | 98.187 | **101.181** | 61.248 | 94.604 | 69.710 |
| `matmul` | 3.362 | 100.676 | **104.038** | 59.079 | 105.270 | 91.850 |
| `json_parse` | 53.154 | 434.289 | **487.443** | 110.510 | 160.883 | 181.111 |
| `nbody` | 4.637 | 127.101 | **131.738** | 60.620 | 128.627 | 100.733 |

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
