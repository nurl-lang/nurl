# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-13T21:25:10Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `bff4e0b5a89522681903f082592a734c18e0f38a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31745263376 |
| NURL | `v0.41.0` |
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
| _(floor: empty program)_ | _1.238_ | _1.235_ | _1.330_ | _16.104_ | _11.694_ |
| `lcg` | 30.328 | 30.318 | **30.299** | 1177.971 | 3247.976 |
| `packet_classifier` | 52.349 | 52.327 | **52.325** | 128.415 | 2578.793 |
| `ring_write` | **32.745** | 33.375 | 32.907 | 50.102 | 4044.743 |
| `histogram_bins` | **31.284** | 31.373 | 31.367 | 52.093 | 3618.789 |
| `prefix_scan` | **16.680** | 16.983 | 17.005 | 49.906 | 2724.771 |
| `binary_search` | **20.102** | 22.298 | 32.782 | 83.841 | 3936.265 |
| `sort_window` | **30.159** | 38.635 | 30.907 | 137.433 | 7465.725 |
| `bloom_filter` | 11.307 | **10.919** | 10.952 | 1853.543 | 5423.704 |
| `hash_join` | **18.053** | 19.774 | 20.179 | 2240.973 | 5148.726 |
| `sieve` | 32.768 | 34.296 | **32.490** | 69.967 | 2069.153 |
| `fib` | **17.560** | 20.578 | 19.444 | 84.924 | 772.579 |
| `collatz` | **13.241** | 13.502 | 14.357 | 52.105 | 489.874 |
| `matmul` | 15.313 | **15.065** | 15.385 | 55.468 | 2020.427 |
| `json_parse` | **5.618** | 6.071 | 7.129 | 24.159 | 23.975 |
| `nbody` | **16.360** | 23.839 | 21.831 | 62.557 | 1586.137 |

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
| _(floor: empty program)_ | _2.068_ | _62.220_ | _**64.288**_ | _40.884_ | _40.887_ | _48.694_ |
| `lcg` | 3.406 | 64.379 | **67.785** | 41.518 | 127.176 | 54.220 |
| `packet_classifier` | 2.195 | 66.090 | **68.285** | 42.118 | 48.903 | 56.020 |
| `ring_write` | 2.246 | 65.213 | **67.459** | 41.234 | 48.859 | 57.660 |
| `histogram_bins` | 2.318 | 77.736 | **80.054** | 40.917 | 49.683 | 58.397 |
| `prefix_scan` | 2.366 | 67.417 | **69.783** | 40.973 | 52.410 | 59.099 |
| `binary_search` | 2.401 | 66.323 | **68.724** | 38.164 | 42.404 | 58.116 |
| `sort_window` | 2.866 | 83.534 | **86.400** | 47.478 | 57.643 | 68.989 |
| `bloom_filter` | 2.601 | 70.668 | **73.269** | 41.179 | 52.085 | 59.932 |
| `hash_join` | 4.172 | 167.782 | **171.954** | 45.885 | 82.430 | 85.673 |
| `sieve` | 2.288 | 62.902 | **65.190** | 39.110 | 50.703 | 64.534 |
| `fib` | 2.167 | 64.076 | **66.243** | 42.323 | 47.058 | 54.941 |
| `collatz` | 2.570 | 73.976 | **76.546** | 46.014 | 51.491 | 62.093 |
| `matmul` | 2.840 | 79.306 | **82.146** | 46.776 | 65.470 | 83.837 |
| `json_parse` | 31.259 | 280.814 | **312.073** | 73.538 | 99.914 | 144.331 |
| `nbody` | 3.171 | 87.696 | **90.867** | 43.300 | 65.755 | 74.040 |

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
