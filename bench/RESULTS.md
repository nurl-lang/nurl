# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-16T13:04:08Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `635c3744b4487e4357e9c515586dcdfd382abd5b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/35099036240 |
| NURL | `v0.66.0-4-g635c3744` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.1 (48a229cea 2026-09-01) |
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
| _(floor: empty program)_ | _1.573_ | _1.550_ | _1.788_ | _25.292_ | _18.199_ |
| `lcg` | 44.006 | **43.981** | 44.177 | 1816.664 | 5540.083 |
| `packet_classifier` | 63.362 | **63.320** | 63.604 | 158.046 | 4748.594 |
| `ring_write` | **47.511** | 47.526 | 47.683 | 71.578 | 6751.930 |
| `histogram_bins` | 44.549 | **44.481** | 44.635 | 73.847 | 6316.884 |
| `prefix_scan` | **24.334** | 24.384 | 24.615 | 72.024 | 4757.376 |
| `binary_search` | 41.380 | **35.764** | 36.469 | 110.693 | 6733.980 |
| `sort_window` | **29.843** | 29.916 | 30.058 | 165.289 | 13103.592 |
| `bloom_filter` | **17.276** | 18.685 | 20.619 | 2851.186 | 8217.106 |
| `hash_join` | **27.589** | 28.615 | 30.038 | 3666.438 | 8283.391 |
| `sieve` | 20.217 | **20.098** | 20.406 | 71.050 | 3462.408 |
| `fib` | **27.922** | 33.150 | 27.979 | 141.488 | 1294.542 |
| `collatz` | 13.648 | **13.632** | 13.805 | 51.953 | 745.716 |
| `matmul` | **45.174** | 46.173 | 45.500 | 82.908 | 3473.523 |
| `json_parse` | 9.440 | **8.789** | 12.074 | 38.619 | 41.108 |
| `nbody` | 26.633 | 44.897 | **26.189** | 96.143 | 3277.257 |

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
| _(floor: empty program)_ | _3.680_ | _104.221_ | _**107.901**_ | _64.798_ | _85.165_ | _65.860_ |
| `lcg` | 3.883 | 115.961 | **119.844** | 66.237 | 95.874 | 73.456 |
| `packet_classifier` | 3.864 | 113.795 | **117.659** | 64.731 | 96.269 | 72.871 |
| `ring_write` | 4.134 | 114.448 | **118.582** | 64.283 | 96.566 | 73.753 |
| `histogram_bins` | 4.273 | 122.897 | **127.170** | 65.312 | 113.302 | 83.375 |
| `prefix_scan` | 4.377 | 119.107 | **123.484** | 66.734 | 105.950 | 80.331 |
| `binary_search` | 4.609 | 118.835 | **123.444** | 67.065 | 102.249 | 81.003 |
| `sort_window` | 4.695 | 118.831 | **123.526** | 65.693 | 109.275 | 85.726 |
| `bloom_filter` | 5.277 | 120.107 | **125.384** | 66.840 | 108.039 | 81.634 |
| `hash_join` | 9.859 | 256.780 | **266.639** | 70.878 | 215.409 | 135.945 |
| `sieve` | 4.332 | 115.440 | **119.772** | 66.107 | 110.177 | 86.627 |
| `fib` | 3.851 | 116.602 | **120.453** | 66.506 | 97.846 | 72.833 |
| `collatz` | 4.212 | 118.050 | **122.262** | 66.257 | 98.345 | 76.357 |
| `matmul` | 4.889 | 116.842 | **121.731** | 66.123 | 110.944 | 98.317 |
| `json_parse` | 104.298 | 459.199 | **563.497** | 167.496 | 163.951 | 187.128 |
| `nbody` | 6.996 | 137.371 | **144.367** | 68.735 | 134.131 | 110.363 |

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
