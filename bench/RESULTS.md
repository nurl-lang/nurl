# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-28T06:21:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `73104171a185b7041b77e4c470cae3416bce107e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33147389325 |
| NURL | `v0.54.0-2-g73104171` |
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
| _(floor: empty program)_ | _1.454_ | _1.436_ | _1.638_ | _23.239_ | _18.043_ |
| `lcg` | 39.208 | **39.005** | 39.260 | 2051.617 | 5455.825 |
| `packet_classifier` | **56.089** | 56.227 | 56.394 | 161.146 | 4366.484 |
| `ring_write` | **42.167** | 42.306 | 42.378 | 66.154 | 6195.960 |
| `histogram_bins` | **39.401** | 40.684 | 39.556 | 66.089 | 6311.542 |
| `prefix_scan` | 21.744 | **21.728** | 21.862 | 66.491 | 4817.787 |
| `binary_search` | **36.139** | 38.121 | 37.080 | 106.649 | 6607.901 |
| `sort_window` | 26.598 | **26.542** | 26.829 | 196.810 | 13284.225 |
| `bloom_filter` | 17.922 | **17.774** | 18.325 | 2845.203 | 7623.910 |
| `hash_join` | **26.858** | 27.822 | 29.337 | 3421.961 | 8826.065 |
| `sieve` | 18.836 | 18.331 | **18.323** | 66.935 | 3387.057 |
| `fib` | **25.057** | 29.907 | 25.293 | 131.221 | 1376.249 |
| `collatz` | 12.205 | **12.110** | 12.322 | 48.220 | 721.853 |
| `matmul` | 33.535 | **33.354** | 33.795 | 75.915 | 3619.494 |
| `json_parse` | 9.001 | **8.671** | 11.648 | 34.840 | 37.407 |
| `nbody` | 25.158 | 39.628 | **24.068** | 100.090 | 3024.968 |

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
| _(floor: empty program)_ | _2.629_ | _92.647_ | _**95.276**_ | _56.953_ | _78.543_ | _61.487_ |
| `lcg` | 2.793 | 93.928 | **96.721** | 57.470 | 89.424 | 68.777 |
| `packet_classifier` | 2.829 | 94.751 | **97.580** | 57.231 | 87.668 | 68.075 |
| `ring_write` | 2.926 | 94.665 | **97.591** | 56.935 | 90.299 | 69.668 |
| `histogram_bins` | 3.102 | 112.177 | **115.279** | 56.771 | 106.378 | 77.925 |
| `prefix_scan` | 3.066 | 97.598 | **100.664** | 57.384 | 94.845 | 73.257 |
| `binary_search` | 3.212 | 103.417 | **106.629** | 58.156 | 97.881 | 75.484 |
| `sort_window` | 3.304 | 104.322 | **107.626** | 58.185 | 101.114 | 82.025 |
| `bloom_filter` | 3.582 | 103.148 | **106.730** | 59.307 | 100.748 | 78.428 |
| `hash_join` | 5.943 | 256.657 | **262.600** | 60.427 | 215.563 | 124.138 |
| `sieve` | 3.147 | 98.052 | **101.199** | 59.059 | 106.828 | 80.384 |
| `fib` | 2.791 | 93.365 | **96.156** | 57.533 | 87.441 | 67.443 |
| `collatz` | 3.006 | 95.702 | **98.708** | 57.394 | 90.607 | 71.420 |
| `matmul` | 3.309 | 98.272 | **101.581** | 57.062 | 103.392 | 91.300 |
| `json_parse` | 53.270 | 430.499 | **483.769** | 108.804 | 160.043 | 179.168 |
| `nbody` | 4.700 | 122.680 | **127.380** | 59.251 | 125.550 | 100.179 |

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
