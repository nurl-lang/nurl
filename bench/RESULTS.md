# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-16T06:21:49Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `71aef979f9c698958684a1ba5b47ed7b608067e1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31931084981 |
| NURL | `v0.43.0-14-g71aef979` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.2 |
| Python | Python 3.12.3 |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `clang -O2`, Rust `-C opt-level=2` |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.256_ | _1.264_ | _1.354_ | _14.906_ | _11.556_ |
| `lcg` | 30.185 | **30.102** | 30.270 | 1057.685 | 3302.438 |
| `packet_classifier` | **52.076** | 52.159 | 52.246 | 125.551 | 2571.070 |
| `ring_write` | **32.750** | 33.260 | 32.817 | 49.632 | 3972.046 |
| `histogram_bins` | 31.310 | **31.271** | 31.370 | 52.217 | 3609.426 |
| `prefix_scan` | **16.706** | 16.986 | 16.958 | 50.985 | 2657.221 |
| `binary_search` | **19.840** | 22.237 | 32.777 | 82.055 | 3929.176 |
| `sort_window` | **30.540** | 38.581 | 30.728 | 132.952 | 7283.253 |
| `bloom_filter` | 12.669 | **12.605** | 12.692 | 1990.755 | 4885.755 |
| `hash_join` | **18.083** | 19.720 | 20.050 | 2258.962 | 5389.583 |
| `sieve` | 33.213 | 32.985 | **32.910** | 68.203 | 1981.023 |
| `fib` | **19.815** | 23.185 | 21.928 | 92.879 | 666.838 |
| `collatz` | **11.335** | 11.511 | 12.259 | 43.213 | 420.368 |
| `matmul` | 15.187 | **15.177** | 15.215 | 54.116 | 2076.303 |
| `json_parse` | **5.568** | 6.052 | 7.123 | 21.854 | 24.231 |
| `nbody` | **16.407** | 23.741 | 21.862 | 62.029 | 1610.680 |

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
| _(floor: empty program)_ | _1.929_ | _53.559_ | _**55.488**_ | _36.153_ | _34.455_ | _49.823_ |
| `lcg` | 2.103 | 57.966 | **60.069** | 36.162 | 42.899 | 57.272 |
| `packet_classifier` | 2.205 | 58.712 | **60.917** | 37.847 | 42.077 | 52.640 |
| `ring_write` | 2.425 | 66.428 | **68.853** | 38.726 | 43.251 | 54.001 |
| `histogram_bins` | 2.371 | 72.276 | **74.647** | 37.963 | 41.903 | 55.817 |
| `prefix_scan` | 2.468 | 63.701 | **66.169** | 38.118 | 48.000 | 56.171 |
| `binary_search` | 2.494 | 65.927 | **68.421** | 38.769 | 43.895 | 60.282 |
| `sort_window` | 2.566 | 68.100 | **70.666** | 39.135 | 46.108 | 65.098 |
| `bloom_filter` | 2.687 | 65.951 | **68.638** | 36.800 | 46.972 | 55.353 |
| `hash_join` | 4.151 | 158.218 | **162.369** | 40.696 | 74.786 | 82.807 |
| `sieve` | 2.331 | 59.289 | **61.620** | 35.902 | 45.463 | 61.710 |
| `fib` | 2.270 | 66.815 | **69.085** | 40.715 | 43.800 | 57.068 |
| `collatz` | 2.368 | 66.309 | **68.677** | 40.533 | 42.314 | 53.087 |
| `matmul` | 2.592 | 60.777 | **63.369** | 36.606 | 46.736 | 70.707 |
| `json_parse` | 33.993 | 268.236 | **302.229** | 70.182 | 73.110 | 139.586 |
| `nbody` | 3.209 | 79.165 | **82.374** | 37.635 | 57.843 | 69.634 |

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
