# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-17T06:40:53Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `1062ac4ca00aaf53e4a71a605a1309835abcf4ec` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32002346038 |
| NURL | `v0.44.2-5-g1062ac4c` |
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
| _(floor: empty program)_ | _1.416_ | _1.546_ | _1.533_ | _20.698_ | _16.371_ |
| `lcg` | 39.199 | **37.559** | 37.651 | 1847.293 | 5359.486 |
| `packet_classifier` | 52.724 | **52.498** | 52.810 | 157.505 | 4373.164 |
| `ring_write` | **40.731** | **40.731** | 40.876 | 68.549 | 6629.931 |
| `histogram_bins` | 40.570 | 41.003 | **39.286** | 67.425 | 6294.266 |
| `prefix_scan` | 21.141 | 21.472 | **20.861** | 67.125 | 4443.416 |
| `binary_search` | **27.414** | 30.066 | 40.929 | 106.042 | 6223.311 |
| `sort_window` | 35.866 | 45.763 | **35.621** | 181.452 | 10986.425 |
| `bloom_filter` | **14.141** | 14.481 | 14.487 | 2782.769 | 7493.648 |
| `hash_join` | **26.089** | 28.148 | 28.309 | 3391.330 | 7863.544 |
| `sieve` | 33.581 | **33.412** | 33.555 | 82.138 | 3286.169 |
| `fib` | 26.058 | 26.488 | **25.303** | 123.601 | 1159.937 |
| `collatz` | 13.020 | **12.742** | 12.823 | 58.179 | 681.859 |
| `matmul` | 17.379 | 17.276 | **17.158** | 73.144 | 3125.838 |
| `json_parse` | **7.310** | 7.508 | 9.539 | 33.319 | 35.391 |
| `nbody` | **21.433** | 36.055 | 33.436 | 92.064 | 2456.427 |

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
| _(floor: empty program)_ | _2.303_ | _78.858_ | _**81.161**_ | _50.419_ | _51.181_ | _56.645_ |
| `lcg` | 2.481 | 80.967 | **83.448** | 51.026 | 56.437 | 61.469 |
| `packet_classifier` | 2.586 | 79.867 | **82.453** | 51.608 | 68.647 | 63.606 |
| `ring_write` | 2.817 | 81.550 | **84.367** | 51.205 | 59.136 | 63.871 |
| `histogram_bins` | 2.750 | 100.258 | **103.008** | 50.411 | 60.440 | 67.377 |
| `prefix_scan` | 2.717 | 86.294 | **89.011** | 50.903 | 63.694 | 67.118 |
| `binary_search` | 3.002 | 88.967 | **91.969** | 50.466 | 58.615 | 67.614 |
| `sort_window` | 2.912 | 92.475 | **95.387** | 51.229 | 66.262 | 71.090 |
| `bloom_filter` | 3.135 | 87.711 | **90.846** | 50.965 | 65.906 | 67.061 |
| `hash_join` | 5.384 | 228.900 | **234.284** | 55.413 | 105.686 | 103.835 |
| `sieve` | 2.819 | 86.483 | **89.302** | 52.194 | 69.967 | 74.619 |
| `fib` | 2.510 | 79.628 | **82.138** | 50.235 | 59.250 | 63.342 |
| `collatz` | 2.667 | 84.486 | **87.153** | 50.734 | 60.070 | 64.440 |
| `matmul` | 2.997 | 85.729 | **88.726** | 51.192 | 71.144 | 85.646 |
| `json_parse` | 48.288 | 379.406 | **427.694** | 98.494 | 108.653 | 175.244 |
| `nbody` | 4.621 | 109.280 | **113.901** | 52.938 | 87.118 | 87.548 |

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
