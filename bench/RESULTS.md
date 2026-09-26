# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-26T14:00:24Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `b83b5a042c77a9f70678a1546754d187fa654fe4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/36246808865 |
| NURL | `v0.66.0-13-gb83b5a04` |
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
| _(floor: empty program)_ | _1.118_ | _1.107_ | _1.251_ | _17.897_ | _13.529_ |
| `lcg` | 35.039 | **34.946** | 35.116 | 1379.008 | 3559.890 |
| `packet_classifier` | 59.796 | **59.767** | 60.342 | 147.268 | 3083.437 |
| `ring_write` | **38.463** | 38.467 | 38.941 | 56.635 | 4349.701 |
| `histogram_bins` | 35.983 | **35.916** | 36.043 | 59.206 | 4176.780 |
| `prefix_scan` | **19.183** | 19.235 | 19.595 | 58.334 | 3157.833 |
| `binary_search` | 33.956 | 27.780 | **26.459** | 95.554 | 4370.124 |
| `sort_window` | **34.351** | 34.531 | 35.320 | 156.248 | 7999.755 |
| `bloom_filter` | 12.573 | **12.540** | 12.879 | 2150.936 | 5541.269 |
| `hash_join` | **21.106** | 22.397 | 22.431 | 2688.171 | 6162.072 |
| `sieve` | 32.407 | **32.109** | 32.180 | 74.991 | 2309.634 |
| `fib` | 25.001 | 25.997 | **24.765** | 97.909 | 796.712 |
| `collatz` | **13.240** | 13.534 | 14.274 | 57.792 | 502.343 |
| `matmul` | 18.037 | **17.851** | 18.016 | 66.067 | 2202.680 |
| `json_parse` | 6.814 | **6.548** | 8.489 | 27.184 | 29.171 |
| `nbody` | **19.572** | 27.878 | 19.712 | 70.769 | 1864.154 |

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
| _(floor: empty program)_ | _2.835_ | _68.093_ | _**70.928**_ | _41.137_ | _50.566_ | _51.552_ |
| `lcg` | 2.717 | 75.475 | **78.192** | 39.134 | 56.450 | 56.261 |
| `packet_classifier` | 2.912 | 77.900 | **80.812** | 41.079 | 57.570 | 53.821 |
| `ring_write` | 3.057 | 75.134 | **78.191** | 40.636 | 57.980 | 55.964 |
| `histogram_bins` | 3.332 | 85.999 | **89.331** | 44.246 | 71.970 | 63.058 |
| `prefix_scan` | 3.279 | 78.358 | **81.637** | 41.940 | 62.658 | 61.706 |
| `binary_search` | 3.427 | 79.005 | **82.432** | 43.271 | 62.900 | 61.911 |
| `sort_window` | 3.619 | 80.840 | **84.459** | 42.414 | 71.440 | 65.805 |
| `bloom_filter` | 4.307 | 89.136 | **93.443** | 47.222 | 67.314 | 60.803 |
| `hash_join` | 7.700 | 196.441 | **204.141** | 52.181 | 159.392 | 107.532 |
| `sieve` | 3.474 | 84.962 | **88.436** | 45.018 | 70.698 | 68.279 |
| `fib` | 3.017 | 79.418 | **82.435** | 43.647 | 60.555 | 54.514 |
| `collatz` | 3.291 | 80.186 | **83.477** | 44.584 | 61.647 | 58.138 |
| `matmul` | 3.718 | 86.684 | **90.402** | 45.708 | 73.423 | 77.219 |
| `json_parse` | 86.263 | 336.635 | **422.898** | 129.593 | 122.742 | 157.242 |
| `nbody` | 5.378 | 92.975 | **98.353** | 45.382 | 86.480 | 86.801 |

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
