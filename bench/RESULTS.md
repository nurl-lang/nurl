# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-27T05:52:34Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ecdd3f7aba51a8247a1a6ff626774639e0309137` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33043649749 |
| NURL | `v0.53.0-4-gecdd3f7a` |
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
| _(floor: empty program)_ | _1.428_ | _1.416_ | _1.637_ | _24.090_ | _18.004_ |
| `lcg` | 39.128 | **38.933** | 39.187 | 2052.987 | 5351.342 |
| `packet_classifier` | 56.356 | **56.262** | 56.502 | 163.219 | 4589.292 |
| `ring_write` | **42.148** | 42.341 | 42.576 | 66.850 | 6705.384 |
| `histogram_bins` | **39.450** | 40.699 | 40.054 | 67.508 | 6122.117 |
| `prefix_scan` | 21.698 | **21.671** | 21.739 | 64.927 | 4502.039 |
| `binary_search` | **36.295** | 38.236 | 37.027 | 105.828 | 6246.297 |
| `sort_window` | **26.486** | 26.540 | 26.734 | 197.935 | 11462.580 |
| `bloom_filter` | 17.828 | **17.825** | 18.388 | 2843.042 | 7697.667 |
| `hash_join` | **26.826** | 27.813 | 29.353 | 3416.505 | 8177.946 |
| `sieve` | 18.333 | **17.876** | 17.905 | 66.022 | 3240.251 |
| `fib` | **25.198** | 29.873 | 25.283 | 133.285 | 1362.873 |
| `collatz` | 12.299 | **12.150** | 12.400 | 50.925 | 718.456 |
| `matmul` | **33.434** | 33.464 | 33.655 | 76.329 | 3303.174 |
| `json_parse` | 8.877 | **8.519** | 11.567 | 35.776 | 37.623 |
| `nbody` | 25.175 | 39.795 | **24.097** | 100.906 | 3017.676 |

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
| _(floor: empty program)_ | _6.358_ | _98.532_ | _**104.890**_ | _64.611_ | _79.540_ | _57.864_ |
| `lcg` | 2.871 | 98.278 | **101.149** | 59.849 | 91.007 | 60.378 |
| `packet_classifier` | 2.909 | 98.302 | **101.211** | 59.716 | 92.445 | 60.528 |
| `ring_write` | 2.965 | 98.180 | **101.145** | 59.106 | 92.163 | 61.614 |
| `histogram_bins` | 3.020 | 113.829 | **116.849** | 58.352 | 110.436 | 68.752 |
| `prefix_scan` | 3.185 | 99.182 | **102.367** | 58.791 | 95.964 | 64.249 |
| `binary_search` | 3.250 | 105.412 | **108.662** | 60.614 | 94.425 | 66.563 |
| `sort_window` | 3.285 | 106.916 | **110.201** | 59.693 | 104.122 | 71.944 |
| `bloom_filter` | 3.538 | 103.914 | **107.452** | 59.430 | 102.379 | 67.728 |
| `hash_join` | 6.024 | 257.526 | **263.550** | 61.519 | 220.204 | 114.590 |
| `sieve` | 3.157 | 99.400 | **102.557** | 58.754 | 102.073 | 70.791 |
| `fib` | 2.809 | 95.281 | **98.090** | 58.809 | 90.073 | 60.481 |
| `collatz` | 2.926 | 97.736 | **100.662** | 58.295 | 90.985 | 61.762 |
| `matmul` | 3.384 | 102.603 | **105.987** | 59.672 | 106.424 | 83.696 |
| `json_parse` | 53.534 | 434.392 | **487.926** | 111.473 | 162.343 | 165.642 |
| `nbody` | 4.659 | 127.550 | **132.209** | 61.668 | 127.892 | 92.492 |

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
