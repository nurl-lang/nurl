# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-02T08:53:39Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377692 KiB |
| Commit | `275ee74d4c1d804f138af7c978ff54ea6b4ee733` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/30740516770 |
| NURL | `v0.30.0-43-g275ee74d` |
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
| _(floor: empty program)_ | _1.664_ | _1.711_ | _1.849_ | _22.510_ | _16.730_ |
| `lcg` | **39.151** | 39.252 | 39.274 | 1879.567 | 5203.930 |
| `packet_classifier` | **56.369** | 56.501 | 56.585 | 159.737 | 4465.686 |
| `ring_write` | **42.271** | 42.350 | 42.487 | 64.430 | 6369.034 |
| `histogram_bins` | **39.671** | 41.378 | 39.769 | 64.595 | 6064.191 |
| `prefix_scan` | **21.825** | 21.917 | 22.203 | 64.889 | 4948.244 |
| `binary_search` | 39.791 | **38.542** | 43.503 | 106.435 | 6117.447 |
| `sort_window` | 27.374 | 27.436 | **26.879** | 196.168 | 11542.950 |
| `bloom_filter` | **18.073** | 18.254 | 18.443 | 2829.566 | 7633.663 |
| `hash_join` | **28.056** | 30.066 | 29.966 | 3425.432 | 8126.207 |
| `sieve` | 18.537 | **17.987** | 18.151 | 63.393 | 3274.893 |
| `fib` | **25.307** | 30.017 | 28.258 | 130.678 | 1377.507 |
| `collatz` | **12.436** | 12.457 | 12.547 | 47.777 | 712.472 |
| `matmul` | **33.381** | 33.532 | 33.798 | 73.857 | 3085.574 |
| `json_parse` | **8.512** | 8.770 | 11.706 | 33.593 | 36.577 |
| `nbody` | 40.852 | 40.908 | **39.079** | 98.932 | 3069.532 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc` emits LLVM IR, then `clang`
lowers and links it against `stdlib/runtime.o`. **NURL total** is the
number comparable to the C and Rust columns. The floor row is what each
toolchain costs for a program that does nothing — for NURL that is
dominated by the LTO link every NURL binary pays for, so subtract it to
read the marginal cost of the benchmark itself. Node and Python have no
column here: they compile at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.548_ | _76.693_ | _**79.241**_ | _54.855_ | _58.429_ |
| `lcg` | 2.628 | 81.630 | **84.258** | 63.804 | 66.252 |
| `packet_classifier` | 2.746 | 82.287 | **85.033** | 65.414 | 65.484 |
| `ring_write` | 2.862 | 83.437 | **86.299** | 65.374 | 67.040 |
| `histogram_bins` | 2.948 | 85.623 | **88.571** | 67.897 | 69.186 |
| `prefix_scan` | 2.907 | 88.685 | **91.592** | 70.040 | 69.603 |
| `binary_search` | 3.021 | 89.159 | **92.180** | 68.462 | 73.004 |
| `sort_window` | 3.076 | 93.271 | **96.347** | 73.884 | 76.306 |
| `bloom_filter` | 3.281 | 91.618 | **94.899** | 74.191 | 77.143 |
| `hash_join` | 5.286 | 204.728 | **210.014** | 116.191 | 108.368 |
| `sieve` | 2.892 | 87.525 | **90.417** | 75.289 | 76.767 |
| `fib` | 2.701 | 80.139 | **82.840** | 63.897 | 64.028 |
| `collatz` | 2.877 | 85.087 | **87.964** | 65.441 | 67.281 |
| `matmul` | 3.162 | 91.410 | **94.572** | 78.209 | 88.896 |
| `json_parse` | 39.731 | 501.850 | **541.581** | 119.886 | 174.898 |
| `nbody` | 4.120 | 101.992 | **106.112** | 94.011 | 89.880 |

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
