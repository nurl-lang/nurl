# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-20T03:32:59Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `15e18f4925632d2c75017bffeb2a84a3663b9e14` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32328330669 |
| NURL | `v0.45.0-14-g15e18f49` |
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
| _(floor: empty program)_ | _1.854_ | _1.918_ | _2.140_ | _27.046_ | _19.536_ |
| `lcg` | **44.627** | 44.650 | 44.775 | 1829.451 | 5317.018 |
| `packet_classifier` | **63.962** | 63.994 | 64.121 | 161.326 | 4948.434 |
| `ring_write` | 48.112 | **48.086** | 48.353 | 75.497 | 6547.845 |
| `histogram_bins` | **45.262** | 45.380 | 45.421 | 78.506 | 6652.591 |
| `prefix_scan` | **25.036** | 25.103 | 25.334 | 76.167 | 4673.965 |
| `binary_search` | **34.777** | 36.501 | 46.452 | 114.118 | 7869.270 |
| `sort_window` | **30.604** | 32.258 | 31.212 | 168.299 | 12614.605 |
| `bloom_filter` | **20.008** | 20.697 | 21.074 | 2740.296 | 8117.881 |
| `hash_join` | **28.115** | 31.358 | 31.808 | 3449.295 | 8267.956 |
| `sieve` | 21.204 | **20.772** | 20.964 | 74.663 | 3485.563 |
| `fib` | **28.479** | 33.998 | 29.933 | 146.773 | 1289.270 |
| `collatz` | 14.200 | **14.095** | 14.303 | 55.968 | 753.260 |
| `matmul` | **46.526** | 47.106 | 46.866 | 86.485 | 3609.137 |
| `json_parse` | **9.238** | 9.241 | 12.401 | 40.521 | 39.887 |
| `nbody` | **27.092** | 46.568 | 44.449 | 97.279 | 3340.434 |

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
| _(floor: empty program)_ | _3.338_ | _101.903_ | _**105.241**_ | _64.948_ | _66.453_ | _70.695_ |
| `lcg` | 3.447 | 112.233 | **115.680** | 68.756 | 77.060 | 79.872 |
| `packet_classifier` | 3.898 | 111.003 | **114.901** | 71.925 | 77.440 | 92.844 |
| `ring_write` | 3.735 | 108.899 | **112.634** | 68.048 | 78.579 | 77.715 |
| `histogram_bins` | 3.775 | 127.386 | **131.161** | 67.438 | 80.075 | 80.960 |
| `prefix_scan` | 3.861 | 112.296 | **116.157** | 68.075 | 83.816 | 81.384 |
| `binary_search` | 3.928 | 116.154 | **120.082** | 67.688 | 79.423 | 106.274 |
| `sort_window` | 6.611 | 124.455 | **131.066** | 78.930 | 88.122 | 94.833 |
| `bloom_filter` | 4.250 | 116.043 | **120.293** | 68.462 | 86.184 | 87.328 |
| `hash_join` | 7.472 | 264.843 | **272.315** | 73.426 | 130.726 | 130.067 |
| `sieve` | 3.907 | 112.232 | **116.139** | 68.327 | 87.568 | 89.895 |
| `fib` | 3.614 | 107.859 | **111.473** | 68.003 | 76.832 | 76.159 |
| `collatz` | 3.694 | 109.208 | **112.902** | 67.010 | 78.086 | 85.783 |
| `matmul` | 3.995 | 113.178 | **117.173** | 65.594 | 88.424 | 109.768 |
| `json_parse` | 53.122 | 423.082 | **476.204** | 119.996 | 127.211 | 193.223 |
| `nbody` | 5.357 | 135.522 | **140.879** | 68.371 | 105.749 | 112.001 |

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
