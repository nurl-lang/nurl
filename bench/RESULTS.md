# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-15T02:33:35Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `f79da81f48963f5848a90574e4f88ef6a04a7da1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31859274646 |
| NURL | `v0.42.0-20-gf79da81f` |
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
| _(floor: empty program)_ | _1.853_ | _1.991_ | _2.242_ | _26.653_ | _19.691_ |
| `lcg` | **39.631** | 39.854 | 39.991 | 2075.273 | 5315.422 |
| `packet_classifier` | 56.837 | **56.813** | 56.831 | 163.751 | 4499.248 |
| `ring_write` | 42.950 | **42.884** | 43.004 | 69.260 | 6216.737 |
| `histogram_bins` | **40.077** | 41.769 | 40.298 | 68.840 | 5947.809 |
| `prefix_scan` | **22.274** | 22.329 | 22.499 | 67.839 | 5408.328 |
| `binary_search` | **36.729** | 38.854 | 44.041 | 110.059 | 6015.035 |
| `sort_window` | **27.253** | 27.879 | 27.429 | 202.818 | 11516.701 |
| `bloom_filter` | **18.343** | 18.613 | 18.984 | 2885.943 | 7775.192 |
| `hash_join` | **27.566** | 30.540 | 30.501 | 3436.569 | 8293.452 |
| `sieve` | 19.370 | 18.951 | **18.944** | 68.708 | 3197.116 |
| `fib` | **25.593** | 30.492 | 28.759 | 134.194 | 1367.999 |
| `collatz` | **12.804** | 12.832 | 13.012 | 52.295 | 714.141 |
| `matmul` | 34.404 | **34.216** | 34.310 | 78.362 | 3159.199 |
| `json_parse` | 9.464 | **9.189** | 12.149 | 37.955 | 40.233 |
| `nbody` | **25.718** | 41.294 | 39.722 | 102.247 | 3036.698 |

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
| _(floor: empty program)_ | _2.988_ | _98.787_ | _**101.775**_ | _63.507_ | _62.494_ | _69.920_ |
| `lcg` | 3.275 | 102.368 | **105.643** | 64.281 | 71.069 | 77.468 |
| `packet_classifier` | 3.437 | 103.957 | **107.394** | 65.252 | 77.900 | 76.949 |
| `ring_write` | 3.139 | 95.393 | **98.532** | 60.237 | 72.147 | 71.700 |
| `histogram_bins` | 3.404 | 122.938 | **126.342** | 64.340 | 76.284 | 79.107 |
| `prefix_scan` | 3.471 | 108.184 | **111.655** | 65.806 | 79.519 | 80.026 |
| `binary_search` | 3.696 | 111.987 | **115.683** | 64.623 | 76.474 | 81.472 |
| `sort_window` | 3.607 | 113.828 | **117.435** | 64.056 | 81.992 | 86.537 |
| `bloom_filter` | 3.815 | 111.244 | **115.059** | 64.822 | 83.732 | 82.694 |
| `hash_join` | 6.041 | 259.172 | **265.213** | 63.423 | 131.247 | 113.012 |
| `sieve` | 3.437 | 102.567 | **106.004** | 62.223 | 81.997 | 115.519 |
| `fib` | 3.141 | 98.732 | **101.873** | 62.782 | 70.772 | 71.590 |
| `collatz` | 3.196 | 101.589 | **104.785** | 62.393 | 72.228 | 74.478 |
| `matmul` | 3.747 | 108.770 | **112.517** | 64.848 | 87.422 | 102.405 |
| `json_parse` | 50.318 | 455.100 | **505.418** | 114.250 | 132.639 | 192.639 |
| `nbody` | 4.880 | 133.341 | **138.221** | 64.585 | 101.485 | 100.595 |

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
