# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-17T08:31:12Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `290b8d84d1a92297835bbaf212b57a9ff2f2bc31` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32010386849 |
| NURL | `v0.44.2-8-g290b8d84` |
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
| _(floor: empty program)_ | _1.833_ | _1.893_ | _2.035_ | _24.760_ | _18.064_ |
| `lcg` | **44.326** | 44.413 | 44.498 | 1816.759 | 5449.086 |
| `packet_classifier` | **63.798** | 63.810 | 63.981 | 157.887 | 4585.376 |
| `ring_write` | **47.881** | 47.956 | 48.074 | 74.060 | 6985.684 |
| `histogram_bins` | **44.871** | 44.953 | 44.997 | 74.753 | 6518.184 |
| `prefix_scan` | **24.713** | 24.791 | 24.969 | 72.446 | 4637.018 |
| `binary_search` | **34.178** | 36.175 | 46.250 | 114.910 | 6590.503 |
| `sort_window` | **30.202** | 30.971 | 30.503 | 165.922 | 11633.058 |
| `bloom_filter` | **19.945** | 20.580 | 20.976 | 2762.094 | 8239.189 |
| `hash_join` | **27.855** | 30.967 | 31.492 | 3427.986 | 8312.791 |
| `sieve` | 20.743 | **20.274** | 20.710 | 71.517 | 3512.948 |
| `fib` | **28.074** | 33.468 | 29.588 | 141.781 | 1289.636 |
| `collatz` | **13.915** | 13.970 | 14.054 | 52.908 | 754.197 |
| `matmul` | 48.175 | **46.841** | 51.043 | 84.338 | 3362.251 |
| `json_parse` | **8.960** | 9.221 | 12.282 | 40.485 | 38.532 |
| `nbody` | **27.108** | 46.553 | 44.275 | 96.866 | 3237.110 |

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
| _(floor: empty program)_ | _3.228_ | _101.104_ | _**104.332**_ | _65.538_ | _68.227_ | _67.363_ |
| `lcg` | 3.430 | 103.136 | **106.566** | 65.698 | 75.006 | 77.054 |
| `packet_classifier` | 3.469 | 103.505 | **106.974** | 66.553 | 76.044 | 75.018 |
| `ring_write` | 3.545 | 104.461 | **108.006** | 65.972 | 76.465 | 75.950 |
| `histogram_bins` | 3.634 | 125.299 | **128.933** | 65.985 | 77.959 | 80.081 |
| `prefix_scan` | 3.762 | 109.547 | **113.309** | 66.598 | 80.579 | 78.993 |
| `binary_search` | 3.869 | 113.828 | **117.697** | 66.056 | 77.309 | 82.293 |
| `sort_window` | 3.865 | 115.433 | **119.298** | 65.873 | 83.315 | 86.138 |
| `bloom_filter` | 4.128 | 112.877 | **117.005** | 66.699 | 83.908 | 82.272 |
| `hash_join` | 6.592 | 253.818 | **260.410** | 68.260 | 123.464 | 116.950 |
| `sieve` | 3.713 | 108.157 | **111.870** | 66.078 | 85.159 | 85.988 |
| `fib` | 3.409 | 102.735 | **106.144** | 66.199 | 74.590 | 73.602 |
| `collatz` | 3.616 | 105.413 | **109.029** | 65.548 | 75.125 | 76.666 |
| `matmul` | 3.979 | 109.538 | **113.517** | 65.894 | 86.521 | 99.206 |
| `json_parse` | 51.746 | 426.368 | **478.114** | 117.067 | 129.851 | 194.132 |
| `nbody` | 5.307 | 135.195 | **140.502** | 67.763 | 103.941 | 101.116 |

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
