# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-14T04:12:48Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `054c38dee18b35fcaf395cd600aee7c25238bca6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31768908066 |
| NURL | `v0.41.0-3-g054c38de` |
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
| _(floor: empty program)_ | _1.654_ | _1.701_ | _1.829_ | _23.247_ | _17.088_ |
| `lcg` | **39.328** | 39.350 | 39.519 | 2057.249 | 5114.584 |
| `packet_classifier` | **56.387** | 56.520 | 56.590 | 161.816 | 4543.322 |
| `ring_write` | **42.347** | 42.402 | 42.604 | 65.606 | 6291.547 |
| `histogram_bins` | **39.759** | 41.437 | 39.765 | 64.997 | 6191.313 |
| `prefix_scan` | **21.835** | 21.925 | 22.114 | 64.849 | 4472.449 |
| `binary_search` | **36.377** | 38.404 | 43.300 | 107.283 | 6199.369 |
| `sort_window` | **26.822** | 27.521 | 26.873 | 197.320 | 11294.830 |
| `bloom_filter` | **18.085** | 18.206 | 18.467 | 2835.499 | 8238.605 |
| `hash_join` | **27.125** | 30.165 | 29.982 | 3426.048 | 8398.877 |
| `sieve` | 18.546 | **18.174** | 18.195 | 64.928 | 3305.425 |
| `fib` | **25.267** | 30.099 | 28.250 | 131.573 | 1370.339 |
| `collatz` | 12.479 | **12.419** | 12.640 | 50.770 | 722.499 |
| `matmul` | 33.617 | **33.581** | 33.761 | 76.583 | 3492.670 |
| `json_parse` | 9.234 | **8.887** | 11.815 | 34.965 | 37.102 |
| `nbody` | **25.308** | 41.055 | 39.012 | 102.739 | 3014.292 |

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
| _(floor: empty program)_ | _2.851_ | _92.972_ | _**95.823**_ | _60.646_ | _58.184_ | _61.239_ |
| `lcg` | 2.925 | 92.800 | **95.725** | 58.457 | 66.566 | 68.562 |
| `packet_classifier` | 2.949 | 93.653 | **96.602** | 58.920 | 68.216 | 67.479 |
| `ring_write` | 3.059 | 92.835 | **95.894** | 59.457 | 68.678 | 68.888 |
| `histogram_bins` | 3.100 | 113.888 | **116.988** | 58.997 | 70.251 | 71.827 |
| `prefix_scan` | 3.132 | 100.431 | **103.563** | 58.936 | 72.169 | 71.699 |
| `binary_search` | 3.279 | 103.376 | **106.655** | 59.428 | 69.261 | 74.576 |
| `sort_window` | 3.338 | 107.546 | **110.884** | 60.863 | 77.211 | 79.625 |
| `bloom_filter` | 3.586 | 103.536 | **107.122** | 59.700 | 77.159 | 74.692 |
| `hash_join` | 5.905 | 256.809 | **262.714** | 61.463 | 119.845 | 109.285 |
| `sieve` | 3.225 | 97.824 | **101.049** | 58.676 | 80.045 | 79.371 |
| `fib` | 2.997 | 93.301 | **96.298** | 59.802 | 66.746 | 67.417 |
| `collatz` | 3.069 | 95.212 | **98.281** | 58.178 | 68.335 | 69.481 |
| `matmul` | 3.412 | 101.403 | **104.815** | 59.543 | 80.853 | 92.615 |
| `json_parse` | 47.075 | 431.207 | **478.282** | 103.546 | 124.169 | 178.829 |
| `nbody` | 4.569 | 124.832 | **129.401** | 60.651 | 96.232 | 93.202 |

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
