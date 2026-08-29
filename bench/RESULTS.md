# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-29T08:11:36Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e9c8a85be3039432ddee64c3e5881db54c6d787c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33242408817 |
| NURL | `v0.54.0-18-ge9c8a85b` |
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
| _(floor: empty program)_ | _1.229_ | _1.199_ | _1.322_ | _22.010_ | _15.197_ |
| `lcg` | 39.331 | **38.967** | 39.032 | 1516.918 | 4034.985 |
| `packet_classifier` | **66.976** | 67.261 | 67.336 | 160.947 | 3375.459 |
| `ring_write` | **42.004** | 42.015 | 42.725 | 61.752 | 4800.898 |
| `histogram_bins` | 40.408 | **40.296** | 40.433 | 65.091 | 4714.011 |
| `prefix_scan` | 21.616 | **21.522** | 22.001 | 65.659 | 3514.115 |
| `binary_search` | 37.728 | 29.802 | **29.575** | 108.036 | 5049.121 |
| `sort_window` | **37.926** | 38.533 | 39.432 | 172.608 | 9047.574 |
| `bloom_filter` | 13.377 | **12.965** | 13.572 | 2285.610 | 6391.335 |
| `hash_join` | **23.157** | 23.928 | 24.234 | 2885.510 | 6773.515 |
| `sieve` | 35.033 | 34.537 | **34.291** | 80.326 | 2600.393 |
| `fib` | 27.278 | 29.394 | **27.014** | 108.315 | 863.810 |
| `collatz` | **14.491** | 14.838 | 14.922 | 57.598 | 543.825 |
| `matmul` | 19.115 | **18.925** | 19.580 | 71.986 | 2363.598 |
| `json_parse` | 7.568 | **7.246** | 9.037 | 30.650 | 31.628 |
| `nbody` | 21.160 | 29.916 | **21.098** | 77.282 | 2052.094 |

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
| _(floor: empty program)_ | _2.251_ | _72.206_ | _**74.457**_ | _45.806_ | _60.386_ | _56.608_ |
| `lcg` | 2.378 | 82.105 | **84.483** | 46.092 | 67.271 | 62.253 |
| `packet_classifier` | 2.558 | 85.967 | **88.525** | 47.471 | 68.938 | 59.636 |
| `ring_write` | 2.619 | 87.177 | **89.796** | 48.219 | 69.484 | 62.605 |
| `histogram_bins` | 2.715 | 96.225 | **98.940** | 48.490 | 85.969 | 81.206 |
| `prefix_scan` | 2.748 | 89.122 | **91.870** | 47.770 | 72.522 | 66.803 |
| `binary_search` | 2.843 | 87.691 | **90.534** | 47.728 | 74.093 | 68.799 |
| `sort_window` | 2.842 | 86.605 | **89.447** | 46.997 | 81.227 | 75.173 |
| `bloom_filter` | 3.095 | 89.629 | **92.724** | 48.682 | 77.295 | 69.709 |
| `hash_join` | 5.439 | 207.096 | **212.535** | 51.270 | 172.590 | 114.321 |
| `sieve` | 2.711 | 87.511 | **90.222** | 48.225 | 80.064 | 74.667 |
| `fib` | 2.486 | 84.093 | **86.579** | 46.668 | 68.519 | 61.941 |
| `collatz` | 2.621 | 86.831 | **89.452** | 46.671 | 69.535 | 65.493 |
| `matmul` | 2.873 | 86.285 | **89.158** | 46.813 | 75.917 | 88.192 |
| `json_parse` | 48.077 | 357.624 | **405.701** | 95.704 | 129.857 | 173.708 |
| `nbody` | 4.122 | 105.130 | **109.252** | 49.901 | 98.906 | 95.142 |

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
