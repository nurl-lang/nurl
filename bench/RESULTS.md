# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-18T21:11:56Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `1a7284a98ac03104f4e60939fc506b58ce21a089` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32186002265 |
| NURL | `v0.45.0` |
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
| _(floor: empty program)_ | _1.636_ | _1.678_ | _1.822_ | _21.032_ | _16.864_ |
| `lcg` | **39.152** | 39.220 | 39.372 | 2052.016 | 5207.276 |
| `packet_classifier` | 56.414 | **56.329** | 56.471 | 160.236 | 4351.915 |
| `ring_write` | 42.381 | **42.359** | 42.436 | 63.751 | 6264.050 |
| `histogram_bins` | **39.764** | 41.441 | 39.867 | 65.865 | 5969.965 |
| `prefix_scan` | **21.905** | 21.923 | 22.048 | 64.327 | 4838.228 |
| `binary_search` | **36.383** | 38.597 | 43.237 | 105.919 | 7145.993 |
| `sort_window` | **26.735** | 27.378 | 26.910 | 196.922 | 11276.457 |
| `bloom_filter` | **18.081** | 18.292 | 18.524 | 2889.373 | 7980.763 |
| `hash_join` | **27.178** | 30.192 | 30.079 | 3416.061 | 8299.157 |
| `sieve` | 19.096 | **17.965** | 18.076 | 66.492 | 3269.216 |
| `fib` | **25.185** | 30.032 | 28.351 | 130.261 | 1364.407 |
| `collatz` | **12.448** | 12.468 | 12.516 | 47.710 | 723.536 |
| `matmul` | 33.533 | **33.506** | 33.698 | 74.078 | 3380.244 |
| `json_parse` | 9.139 | **8.775** | 11.745 | 33.962 | 37.160 |
| `nbody` | **25.610** | 40.940 | 39.228 | 100.875 | 3027.748 |

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
| _(floor: empty program)_ | _2.754_ | _86.395_ | _**89.149**_ | _56.867_ | _55.256_ | _60.082_ |
| `lcg` | 2.900 | 87.968 | **90.868** | 55.492 | 63.670 | 68.254 |
| `packet_classifier` | 2.969 | 87.697 | **90.666** | 55.474 | 64.634 | 67.425 |
| `ring_write` | 3.123 | 89.739 | **92.862** | 56.052 | 66.698 | 69.010 |
| `histogram_bins` | 3.216 | 113.061 | **116.277** | 57.888 | 70.037 | 71.732 |
| `prefix_scan` | 3.217 | 95.265 | **98.482** | 57.350 | 70.576 | 72.746 |
| `binary_search` | 3.358 | 99.789 | **103.147** | 56.963 | 68.030 | 75.393 |
| `sort_window` | 3.413 | 102.774 | **106.187** | 57.007 | 73.903 | 76.961 |
| `bloom_filter` | 3.667 | 100.030 | **103.697** | 57.288 | 74.459 | 73.228 |
| `hash_join` | 6.114 | 250.692 | **256.806** | 59.572 | 117.332 | 108.166 |
| `sieve` | 3.302 | 94.101 | **97.403** | 57.226 | 75.765 | 77.888 |
| `fib` | 2.982 | 88.806 | **91.788** | 56.960 | 64.062 | 66.463 |
| `collatz` | 3.192 | 91.767 | **94.959** | 55.866 | 65.257 | 68.226 |
| `matmul` | 3.505 | 96.998 | **100.503** | 56.674 | 79.769 | 90.226 |
| `json_parse` | 51.279 | 424.340 | **475.619** | 106.920 | 121.324 | 175.062 |
| `nbody` | 4.787 | 125.076 | **129.863** | 58.830 | 98.152 | 94.398 |

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
