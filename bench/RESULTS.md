# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-25T23:16:16Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `c46413898090ae1cd850d4daa8af6a48c47e649f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32909733868 |
| NURL | `v0.52.0-14-gc4641389` |
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
| _(floor: empty program)_ | _1.093_ | _1.097_ | _1.236_ | _15.707_ | _11.073_ |
| `lcg` | **27.763** | 27.829 | 28.029 | 1058.291 | 2857.804 |
| `packet_classifier` | 40.091 | **40.053** | 40.178 | 121.669 | 2486.233 |
| `ring_write` | 27.872 | **27.811** | 27.959 | 46.252 | 3442.923 |
| `histogram_bins` | 27.816 | **27.796** | 27.952 | 45.744 | 3533.218 |
| `prefix_scan` | **15.331** | 15.362 | 15.461 | 44.355 | 2437.574 |
| `binary_search` | 14.044 | **13.910** | 14.765 | 63.479 | 3492.680 |
| `sort_window` | 19.452 | **19.301** | 19.559 | 125.509 | 6327.640 |
| `bloom_filter` | 8.444 | **8.415** | 8.608 | 1545.886 | 4314.686 |
| `hash_join` | **15.377** | 16.535 | 17.207 | 1844.535 | 4262.600 |
| `sieve` | 11.260 | **11.130** | 11.496 | 41.972 | 1794.988 |
| `fib` | 18.382 | **18.270** | 18.544 | 72.272 | 684.956 |
| `collatz` | 8.894 | **8.874** | 8.959 | 32.127 | 440.374 |
| `matmul` | 19.692 | 19.724 | **19.549** | 49.417 | 1653.175 |
| `json_parse` | **4.812** | 4.814 | 6.534 | 22.244 | 21.487 |
| `nbody` | **16.089** | 23.923 | 16.220 | 54.277 | 1409.505 |

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
| _(floor: empty program)_ | _1.992_ | _66.030_ | _**68.022**_ | _41.166_ | _56.645_ | _40.004_ |
| `lcg` | 2.080 | 67.214 | **69.294** | 41.666 | 63.484 | 47.636 |
| `packet_classifier` | 2.150 | 67.903 | **70.053** | 41.822 | 63.916 | 45.631 |
| `ring_write` | 2.186 | 67.721 | **69.907** | 42.002 | 64.687 | 46.387 |
| `histogram_bins` | 2.258 | 78.160 | **80.418** | 42.047 | 74.622 | 50.315 |
| `prefix_scan` | 2.292 | 69.207 | **71.499** | 41.781 | 68.459 | 48.410 |
| `binary_search` | 2.334 | 71.203 | **73.537** | 42.055 | 66.076 | 49.714 |
| `sort_window` | 2.464 | 74.188 | **76.652** | 42.400 | 72.289 | 53.115 |
| `bloom_filter` | 2.540 | 71.613 | **74.153** | 42.164 | 70.736 | 50.715 |
| `hash_join` | 3.864 | 154.152 | **158.016** | 44.037 | 130.658 | 81.031 |
| `sieve` | 2.270 | 69.206 | **71.476** | 41.739 | 70.698 | 53.334 |
| `fib` | 2.136 | 66.333 | **68.469** | 41.617 | 64.637 | 45.512 |
| `collatz` | 2.215 | 68.710 | **70.925** | 41.479 | 65.457 | 47.146 |
| `matmul` | 2.414 | 70.793 | **73.207** | 42.349 | 72.477 | 62.119 |
| `json_parse` | 28.913 | 251.833 | **280.746** | 69.383 | 104.790 | 116.706 |
| `nbody` | 3.080 | 86.287 | **89.367** | 43.064 | 84.010 | 66.086 |

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
