# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-28T10:15:16Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `8fa39aa44fd7e73f3e7971c0fd86c456b9aca198` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33162350951 |
| NURL | `v0.54.0-4-g8fa39aa4` |
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
| _(floor: empty program)_ | _1.440_ | _1.422_ | _1.652_ | _23.563_ | _17.998_ |
| `lcg` | 39.041 | **38.994** | 39.202 | 2043.641 | 5166.300 |
| `packet_classifier` | 56.351 | **56.226** | 56.428 | 162.985 | 4444.895 |
| `ring_write` | **42.135** | 42.183 | 42.411 | 66.958 | 6419.426 |
| `histogram_bins` | **39.429** | 40.720 | 39.743 | 66.104 | 6266.247 |
| `prefix_scan` | **21.724** | 21.777 | 21.988 | 66.662 | 4498.915 |
| `binary_search` | 39.341 | 38.193 | **36.972** | 105.343 | 6100.835 |
| `sort_window` | **26.537** | 26.578 | 26.744 | 197.321 | 11434.676 |
| `bloom_filter` | **17.711** | 17.749 | 18.206 | 2831.014 | 7520.763 |
| `hash_join` | **27.059** | 28.115 | 29.399 | 3415.136 | 8244.747 |
| `sieve` | 20.465 | **20.238** | 20.261 | 67.065 | 3482.135 |
| `fib` | **24.957** | 29.643 | 25.227 | 131.414 | 1371.966 |
| `collatz` | 12.270 | **12.213** | 12.324 | 50.733 | 719.225 |
| `matmul` | **33.496** | 33.542 | 33.670 | 78.314 | 4716.585 |
| `json_parse` | 8.872 | **8.582** | 11.620 | 36.237 | 39.455 |
| `nbody` | 25.181 | 39.798 | **24.165** | 102.450 | 3053.095 |

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
| _(floor: empty program)_ | _2.729_ | _98.134_ | _**100.863**_ | _59.593_ | _78.720_ | _61.665_ |
| `lcg` | 2.825 | 107.264 | **110.089** | 58.970 | 87.345 | 69.535 |
| `packet_classifier` | 2.881 | 106.215 | **109.096** | 59.271 | 89.953 | 69.397 |
| `ring_write` | 2.985 | 108.952 | **111.937** | 59.157 | 91.865 | 72.184 |
| `histogram_bins` | 3.099 | 115.545 | **118.644** | 58.578 | 106.405 | 77.813 |
| `prefix_scan` | 3.175 | 111.191 | **114.366** | 62.621 | 108.217 | 75.589 |
| `binary_search` | 3.252 | 107.694 | **110.946** | 60.257 | 94.769 | 75.968 |
| `sort_window` | 3.311 | 107.989 | **111.300** | 59.162 | 102.924 | 81.838 |
| `bloom_filter` | 3.492 | 108.194 | **111.686** | 59.335 | 99.824 | 76.528 |
| `hash_join` | 5.963 | 255.518 | **261.481** | 60.686 | 216.290 | 123.949 |
| `sieve` | 3.120 | 105.107 | **108.227** | 58.784 | 101.717 | 86.949 |
| `fib` | 2.768 | 104.332 | **107.100** | 57.682 | 91.340 | 67.995 |
| `collatz` | 3.005 | 106.721 | **109.726** | 59.007 | 90.280 | 71.662 |
| `matmul` | 3.364 | 110.677 | **114.041** | 61.147 | 108.898 | 95.331 |
| `json_parse` | 54.439 | 437.099 | **491.538** | 113.222 | 159.361 | 177.379 |
| `nbody` | 4.764 | 130.772 | **135.536** | 62.038 | 126.376 | 102.165 |

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
