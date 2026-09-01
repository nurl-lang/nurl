# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-01T04:27:32Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `6cb2904863edd6f1bbc08ec3cb52eac99452f24f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33469621658 |
| NURL | `v0.57.0-9-g6cb29048` |
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
| _(floor: empty program)_ | _1.541_ | _1.522_ | _1.747_ | _23.651_ | _17.902_ |
| `lcg` | 44.026 | **43.975** | 44.283 | 1823.108 | 5300.824 |
| `packet_classifier` | **63.437** | 63.524 | 63.790 | 158.430 | 4561.890 |
| `ring_write` | **47.528** | 47.558 | 47.795 | 72.979 | 6634.130 |
| `histogram_bins` | **44.578** | 44.604 | 44.918 | 75.241 | 6453.012 |
| `prefix_scan` | 24.381 | **24.340** | 24.615 | 71.079 | 5606.003 |
| `binary_search` | 41.473 | **35.659** | 36.644 | 111.270 | 6411.892 |
| `sort_window` | **29.931** | 29.992 | 30.241 | 164.706 | 12361.987 |
| `bloom_filter` | 19.703 | **18.741** | 20.698 | 2758.497 | 7635.756 |
| `hash_join` | **27.543** | 28.610 | 30.081 | 3426.485 | 8335.606 |
| `sieve` | 20.442 | **19.917** | 20.323 | 72.196 | 3413.845 |
| `fib` | **27.834** | 33.095 | 28.062 | 143.218 | 1307.047 |
| `collatz` | 13.652 | **13.642** | 13.796 | 53.226 | 752.636 |
| `matmul` | **45.687** | 46.233 | 46.732 | 83.763 | 3643.269 |
| `json_parse` | **8.659** | 8.793 | 12.168 | 39.122 | 38.100 |
| `nbody` | 26.642 | 44.904 | **26.224** | 97.805 | 3190.478 |

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
| _(floor: empty program)_ | _3.048_ | _103.430_ | _**106.478**_ | _64.057_ | _85.837_ | _65.531_ |
| `lcg` | 3.168 | 113.011 | **116.179** | 64.583 | 97.756 | 75.323 |
| `packet_classifier` | 3.185 | 113.314 | **116.499** | 64.147 | 99.207 | 75.671 |
| `ring_write` | 3.298 | 112.945 | **116.243** | 64.192 | 99.254 | 78.212 |
| `histogram_bins` | 3.408 | 124.672 | **128.080** | 65.681 | 117.699 | 84.406 |
| `prefix_scan` | 3.404 | 117.028 | **120.432** | 65.744 | 105.697 | 81.054 |
| `binary_search` | 3.666 | 117.511 | **121.177** | 65.398 | 101.145 | 80.765 |
| `sort_window` | 3.664 | 119.438 | **123.102** | 65.864 | 111.876 | 86.071 |
| `bloom_filter` | 3.950 | 119.026 | **122.976** | 65.062 | 110.751 | 84.349 |
| `hash_join` | 6.462 | 255.649 | **262.111** | 69.036 | 215.277 | 131.843 |
| `sieve` | 3.506 | 121.457 | **124.963** | 64.735 | 111.814 | 87.581 |
| `fib` | 3.155 | 112.972 | **116.127** | 64.110 | 96.656 | 73.225 |
| `collatz` | 3.366 | 118.668 | **122.034** | 65.627 | 98.552 | 76.782 |
| `matmul` | 3.710 | 117.576 | **121.286** | 65.896 | 113.242 | 100.854 |
| `json_parse` | 55.037 | 427.787 | **482.824** | 118.247 | 162.801 | 191.840 |
| `nbody` | 5.053 | 135.490 | **140.543** | 66.425 | 132.720 | 109.485 |

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
