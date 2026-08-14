# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-14T08:29:50Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373460 KiB |
| Commit | `aa8e46854c344ec95a5fbac38400c32f35835ea6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31783861507 |
| NURL | `v0.41.0-8-gaa8e4685` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.1 |
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
| _(floor: empty program)_ | _1.458_ | _1.487_ | _1.611_ | _20.050_ | _15.211_ |
| `lcg` | **34.451** | 34.554 | 34.714 | 1421.717 | 4170.805 |
| `packet_classifier` | **49.466** | 49.608 | 49.757 | 124.249 | 3569.660 |
| `ring_write` | **37.134** | 37.228 | 37.275 | 57.271 | 5298.684 |
| `histogram_bins` | **34.742** | 34.764 | 34.922 | 57.586 | 5456.584 |
| `prefix_scan` | **19.126** | 19.197 | 19.310 | 55.213 | 3647.605 |
| `binary_search` | **26.078** | 28.011 | 35.841 | 86.243 | 4940.413 |
| `sort_window` | **23.437** | 24.016 | 23.581 | 132.301 | 8469.206 |
| `bloom_filter` | **15.473** | 15.998 | 16.263 | 2145.881 | 6056.811 |
| `hash_join` | **21.617** | 24.064 | 24.322 | 2669.211 | 6341.772 |
| `sieve` | 16.352 | **16.008** | 16.112 | 56.210 | 2974.588 |
| `fib` | **21.855** | 25.977 | 22.890 | 110.548 | 1001.389 |
| `collatz` | 10.877 | **10.850** | 10.964 | 40.753 | 586.987 |
| `matmul` | 36.657 | **36.219** | 37.053 | 67.249 | 2865.055 |
| `json_parse` | **6.988** | 7.134 | 9.640 | 30.470 | 29.828 |
| `nbody` | **21.039** | 36.154 | 34.431 | 76.493 | 2544.822 |

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
| _(floor: empty program)_ | _2.465_ | _81.413_ | _**83.878**_ | _57.252_ | _54.432_ | _54.868_ |
| `lcg` | 2.616 | 83.792 | **86.408** | 53.506 | 60.396 | 62.189 |
| `packet_classifier` | 2.665 | 84.061 | **86.726** | 53.859 | 60.700 | 60.936 |
| `ring_write` | 2.666 | 81.399 | **84.065** | 52.018 | 59.752 | 61.118 |
| `histogram_bins` | 2.768 | 98.259 | **101.027** | 52.815 | 61.866 | 62.700 |
| `prefix_scan` | 2.822 | 86.157 | **88.979** | 52.581 | 63.287 | 62.755 |
| `binary_search` | 2.906 | 88.789 | **91.695** | 52.612 | 61.151 | 65.603 |
| `sort_window` | 2.908 | 90.520 | **93.428** | 51.721 | 64.668 | 67.432 |
| `bloom_filter` | 3.094 | 87.814 | **90.908** | 52.402 | 66.981 | 65.406 |
| `hash_join` | 5.007 | 202.097 | **207.104** | 55.924 | 98.836 | 94.102 |
| `sieve` | 2.766 | 85.038 | **87.804** | 52.142 | 67.243 | 69.152 |
| `fib` | 2.661 | 81.934 | **84.595** | 53.019 | 58.665 | 58.683 |
| `collatz` | 2.676 | 82.729 | **85.405** | 52.528 | 59.835 | 62.774 |
| `matmul` | 2.960 | 88.222 | **91.182** | 53.049 | 68.842 | 80.049 |
| `json_parse` | 36.629 | 329.785 | **366.414** | 88.608 | 100.521 | 150.552 |
| `nbody` | 3.931 | 108.026 | **111.957** | 54.018 | 80.983 | 81.020 |

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
