# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-12T04:19:22Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `77bf2d802e87bef93edac5ed170050114e2ebd6b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34672507813 |
| NURL | `v0.63.0-14-g77bf2d80` |
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
| _(floor: empty program)_ | _1.197_ | _1.167_ | _1.366_ | _20.371_ | _15.055_ |
| `lcg` | **38.188** | 39.289 | 38.640 | 1517.255 | 4176.275 |
| `packet_classifier` | **66.007** | 66.669 | 66.736 | 162.481 | 3369.466 |
| `ring_write` | 42.881 | 42.607 | **42.208** | 63.506 | 5465.692 |
| `histogram_bins` | **39.383** | 39.531 | 39.513 | 67.185 | 4730.544 |
| `prefix_scan` | **21.256** | 21.375 | 21.973 | 63.827 | 3682.292 |
| `binary_search` | 38.151 | 31.219 | **29.369** | 107.506 | 4934.280 |
| `sort_window` | **38.248** | 38.522 | 39.202 | 174.828 | 8973.716 |
| `bloom_filter` | 13.765 | **13.714** | 14.271 | 2356.095 | 6387.757 |
| `hash_join` | **23.125** | 23.892 | 24.536 | 2941.669 | 6870.861 |
| `sieve` | 35.891 | **35.013** | 35.976 | 82.849 | 2676.832 |
| `fib` | **27.107** | 29.788 | 28.111 | 109.248 | 864.075 |
| `collatz` | **14.141** | 14.729 | 15.380 | 55.976 | 546.581 |
| `matmul` | **19.603** | 19.681 | 19.726 | 70.125 | 2514.957 |
| `json_parse` | 8.638 | **7.230** | 9.066 | 29.693 | 31.274 |
| `nbody` | **21.550** | 30.325 | 21.714 | 78.617 | 2124.362 |

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
| _(floor: empty program)_ | _2.698_ | _75.001_ | _**77.699**_ | _45.576_ | _58.156_ | _54.949_ |
| `lcg` | 2.875 | 85.164 | **88.039** | 46.608 | 66.051 | 61.619 |
| `packet_classifier` | 2.966 | 86.113 | **89.079** | 45.900 | 67.110 | 61.076 |
| `ring_write` | 3.228 | 85.504 | **88.732** | 47.408 | 68.115 | 61.116 |
| `histogram_bins` | 3.340 | 94.377 | **97.717** | 48.198 | 84.871 | 69.834 |
| `prefix_scan` | 3.373 | 89.969 | **93.342** | 48.698 | 74.062 | 63.528 |
| `binary_search` | 3.583 | 88.392 | **91.975** | 48.652 | 71.391 | 67.550 |
| `sort_window` | 3.752 | 92.603 | **96.355** | 50.114 | 80.588 | 70.811 |
| `bloom_filter` | 4.078 | 90.084 | **94.162** | 48.151 | 76.372 | 64.517 |
| `hash_join` | 7.996 | 211.390 | **219.386** | 54.572 | 172.312 | 117.513 |
| `sieve` | 3.347 | 88.443 | **91.790** | 48.374 | 76.851 | 72.385 |
| `fib` | 2.978 | 86.453 | **89.431** | 47.571 | 68.532 | 59.448 |
| `collatz` | 3.300 | 89.192 | **92.492** | 47.765 | 68.431 | 64.376 |
| `matmul` | 3.667 | 85.543 | **89.210** | 47.719 | 77.405 | 85.234 |
| `json_parse` | 86.791 | 395.218 | **482.009** | 134.842 | 127.783 | 171.869 |
| `nbody` | 5.462 | 103.387 | **108.849** | 49.245 | 99.795 | 94.006 |

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
