# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-28T13:33:36Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `74c26028dd6cc69bd5d0045ab373df5fd2fe8a78` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/36429029458 |
| NURL | `v0.66.0-15-g74c26028` |
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
| _(floor: empty program)_ | _1.140_ | _1.132_ | _1.324_ | _16.733_ | _11.831_ |
| `lcg` | **29.448** | 29.738 | 29.915 | 1133.921 | 3043.014 |
| `packet_classifier` | 43.212 | **43.109** | 43.321 | 133.027 | 2738.639 |
| `ring_write` | 30.012 | **29.705** | 29.880 | 51.034 | 3788.703 |
| `histogram_bins` | 30.124 | **29.819** | 29.901 | 51.320 | 3565.400 |
| `prefix_scan` | 16.580 | **16.506** | 16.702 | 50.886 | 2599.450 |
| `binary_search` | 15.267 | **14.973** | 16.076 | 71.772 | 3598.012 |
| `sort_window` | 20.639 | **20.499** | 20.751 | 135.928 | 6230.235 |
| `bloom_filter` | 8.994 | **8.764** | 8.870 | 1587.707 | 4226.348 |
| `hash_join` | **16.143** | 16.339 | 17.381 | 1878.071 | 4392.735 |
| `sieve` | 11.518 | **11.499** | 11.555 | 43.751 | 1775.662 |
| `fib` | 19.268 | 18.985 | **18.842** | 75.469 | 681.949 |
| `collatz` | 9.461 | **9.365** | 9.521 | 36.437 | 418.087 |
| `matmul` | **19.703** | 20.126 | 20.052 | 52.066 | 1821.358 |
| `json_parse` | **4.966** | 5.408 | 6.946 | 25.961 | 26.305 |
| `nbody` | 17.246 | 25.468 | **16.711** | 62.708 | 1515.656 |

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
| _(floor: empty program)_ | _2.945_ | _78.749_ | _**81.694**_ | _49.131_ | _68.234_ | _50.390_ |
| `lcg` | 2.855 | 84.155 | **87.010** | 47.266 | 72.614 | 56.736 |
| `packet_classifier` | 2.979 | 87.471 | **90.450** | 47.681 | 73.530 | 58.181 |
| `ring_write` | 3.081 | 88.418 | **91.499** | 49.220 | 77.106 | 60.165 |
| `histogram_bins` | 3.399 | 92.960 | **96.359** | 49.540 | 85.995 | 64.467 |
| `prefix_scan` | 3.191 | 90.070 | **93.261** | 50.893 | 80.838 | 62.827 |
| `binary_search` | 3.525 | 96.213 | **99.738** | 52.773 | 81.919 | 67.211 |
| `sort_window` | 3.396 | 89.561 | **92.957** | 48.645 | 81.193 | 65.926 |
| `bloom_filter` | 3.705 | 89.914 | **93.619** | 49.591 | 81.699 | 63.096 |
| `hash_join` | 6.012 | 163.706 | **169.718** | 48.357 | 142.458 | 91.213 |
| `sieve` | 3.153 | 82.106 | **85.259** | 45.645 | 76.635 | 62.486 |
| `fib` | 2.914 | 87.393 | **90.307** | 48.194 | 72.116 | 57.204 |
| `collatz` | 3.045 | 86.027 | **89.072** | 47.654 | 75.082 | 58.774 |
| `matmul` | 3.457 | 84.829 | **88.286** | 48.052 | 79.764 | 75.227 |
| `json_parse` | 65.261 | 303.440 | **368.701** | 112.550 | 135.575 | 147.853 |
| `nbody` | 4.777 | 104.576 | **109.353** | 51.136 | 97.267 | 88.650 |

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
