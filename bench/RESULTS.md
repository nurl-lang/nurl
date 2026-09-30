# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-30T10:45:16Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `7a7f629db99cd8b0bc95dd997ade63f3444410a8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/36703831944 |
| NURL | `v0.67.0-7-g7a7f629d` |
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
| _(floor: empty program)_ | _1.563_ | _1.542_ | _1.756_ | _24.053_ | _17.740_ |
| `lcg` | 44.074 | **44.007** | 44.244 | 1818.770 | 5755.549 |
| `packet_classifier` | 63.474 | **63.392** | 63.653 | 156.925 | 4764.686 |
| `ring_write` | 47.576 | **47.559** | 47.823 | 72.872 | 6644.919 |
| `histogram_bins` | **44.522** | 44.533 | 44.737 | 75.325 | 6319.698 |
| `prefix_scan` | **24.376** | 24.382 | 24.644 | 72.382 | 4845.156 |
| `binary_search` | 41.445 | **35.481** | 36.486 | 111.813 | 6495.692 |
| `sort_window` | 29.932 | **29.860** | 30.158 | 168.779 | 11305.219 |
| `bloom_filter` | **17.241** | 18.658 | 20.632 | 2725.359 | 7786.019 |
| `hash_join` | **27.503** | 28.563 | 30.055 | 3436.990 | 8285.555 |
| `sieve` | 20.315 | 20.140 | **20.078** | 71.759 | 3509.302 |
| `fib` | **27.804** | 33.084 | 27.964 | 142.131 | 1336.895 |
| `collatz` | 13.705 | **13.624** | 13.862 | 51.685 | 750.830 |
| `matmul` | 45.920 | 46.400 | **45.608** | 83.021 | 3336.716 |
| `json_parse` | **8.438** | 8.846 | 12.046 | 41.011 | 40.024 |
| `nbody` | 26.686 | 44.911 | **26.281** | 94.394 | 3276.807 |

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
| _(floor: empty program)_ | _3.726_ | _109.860_ | _**113.586**_ | _66.772_ | _87.068_ | _65.524_ |
| `lcg` | 3.976 | 117.444 | **121.420** | 66.608 | 97.314 | 74.639 |
| `packet_classifier` | 4.020 | 117.016 | **121.036** | 66.590 | 98.320 | 73.862 |
| `ring_write` | 4.328 | 117.355 | **121.683** | 66.370 | 99.497 | 75.188 |
| `histogram_bins` | 4.400 | 125.824 | **130.224** | 66.519 | 116.494 | 84.204 |
| `prefix_scan` | 4.438 | 119.789 | **124.227** | 66.505 | 105.074 | 79.468 |
| `binary_search` | 4.527 | 118.394 | **122.921** | 66.347 | 100.464 | 81.174 |
| `sort_window` | 4.831 | 122.556 | **127.387** | 67.563 | 111.075 | 85.515 |
| `bloom_filter` | 5.281 | 122.603 | **127.884** | 68.378 | 110.032 | 82.108 |
| `hash_join` | 9.706 | 258.024 | **267.730** | 72.275 | 215.965 | 130.186 |
| `sieve` | 4.544 | 118.519 | **123.063** | 67.761 | 109.718 | 85.610 |
| `fib` | 4.020 | 118.312 | **122.332** | 67.447 | 97.786 | 73.048 |
| `collatz` | 4.368 | 119.646 | **124.014** | 67.440 | 99.112 | 76.016 |
| `matmul` | 4.945 | 118.650 | **123.595** | 67.062 | 112.481 | 99.875 |
| `json_parse` | 101.992 | 439.703 | **541.695** | 166.311 | 163.682 | 185.274 |
| `nbody` | 6.983 | 137.679 | **144.662** | 70.362 | 134.213 | 109.028 |

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
