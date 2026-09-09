# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-09T20:14:04Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `870bf2ba9cf1317a5c4b38f1cd4f81200b3d630b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34399204381 |
| NURL | `v0.62.0-9-g870bf2ba` |
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
| _(floor: empty program)_ | _1.414_ | _1.395_ | _1.609_ | _23.770_ | _16.819_ |
| `lcg` | 39.091 | **39.047** | 39.152 | 2049.141 | 5545.417 |
| `packet_classifier` | 56.352 | **56.296** | 56.519 | 162.159 | 4426.355 |
| `ring_write` | **42.050** | 42.115 | 42.208 | 65.056 | 6283.507 |
| `histogram_bins` | **39.450** | 40.502 | 39.622 | 66.782 | 6360.940 |
| `prefix_scan` | 21.725 | **21.628** | 21.705 | 64.852 | 4534.023 |
| `binary_search` | 39.405 | 38.059 | **36.857** | 103.821 | 6232.554 |
| `sort_window` | 26.565 | **26.562** | 26.791 | 197.481 | 11265.173 |
| `bloom_filter` | 17.741 | **17.703** | 18.195 | 2845.922 | 7559.298 |
| `hash_join` | **26.694** | 27.695 | 29.195 | 3412.609 | 8561.352 |
| `sieve` | 18.174 | **17.862** | 18.006 | 65.299 | 3284.197 |
| `fib` | **25.003** | 29.640 | 25.171 | 130.134 | 1396.675 |
| `collatz` | 12.182 | **12.105** | 12.354 | 48.683 | 724.255 |
| `matmul` | 33.287 | **33.244** | 33.351 | 75.840 | 3309.068 |
| `json_parse` | 9.043 | **8.540** | 11.456 | 35.244 | 38.086 |
| `nbody` | 25.084 | 39.736 | **24.002** | 101.853 | 3313.934 |

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
| _(floor: empty program)_ | _2.630_ | _92.076_ | _**94.706**_ | _60.239_ | _76.061_ | _52.924_ |
| `lcg` | 2.734 | 103.456 | **106.190** | 57.192 | 86.620 | 58.885 |
| `packet_classifier` | 2.840 | 104.873 | **107.713** | 57.574 | 88.333 | 58.603 |
| `ring_write` | 2.977 | 108.884 | **111.861** | 59.770 | 92.505 | 60.048 |
| `histogram_bins` | 3.037 | 116.549 | **119.586** | 58.960 | 108.431 | 67.427 |
| `prefix_scan` | 3.118 | 107.317 | **110.435** | 57.889 | 94.339 | 62.955 |
| `binary_search` | 3.211 | 105.478 | **108.689** | 57.683 | 89.915 | 64.097 |
| `sort_window` | 3.260 | 110.679 | **113.939** | 59.416 | 101.605 | 69.492 |
| `bloom_filter` | 3.498 | 108.246 | **111.744** | 57.881 | 97.432 | 64.712 |
| `hash_join` | 6.046 | 255.220 | **261.266** | 61.199 | 215.749 | 111.588 |
| `sieve` | 3.046 | 104.643 | **107.689** | 57.449 | 97.573 | 68.888 |
| `fib` | 2.833 | 102.849 | **105.682** | 57.126 | 85.219 | 57.796 |
| `collatz` | 2.973 | 105.844 | **108.817** | 57.166 | 87.802 | 59.641 |
| `matmul` | 3.322 | 105.699 | **109.021** | 57.765 | 101.339 | 81.307 |
| `json_parse` | 57.519 | 448.981 | **506.500** | 114.274 | 159.837 | 162.694 |
| `nbody` | 4.696 | 126.946 | **131.642** | 59.980 | 126.091 | 90.398 |

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
