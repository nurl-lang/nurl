# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-13T19:29:10Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1020-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372448 KiB |
| Commit | `acd467d73e04e203ba719f80e0fa28c04c390d38` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31735692002 |
| NURL | `v0.40.0-9-gacd467d7` |
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
| _(floor: empty program)_ | _1.460_ | _1.486_ | _1.579_ | _23.762_ | _16.991_ |
| `lcg` | 41.937 | 41.966 | **41.928** | 1538.496 | 4435.645 |
| `packet_classifier` | 72.569 | 73.405 | **71.049** | 173.056 | 3611.915 |
| `ring_write` | 45.973 | **45.907** | 46.241 | 70.828 | 5279.831 |
| `histogram_bins` | 43.067 | **42.928** | 43.206 | 70.531 | 5082.481 |
| `prefix_scan` | **23.153** | 23.312 | 23.733 | 68.911 | 3673.242 |
| `binary_search` | **27.905** | 33.025 | 47.123 | 116.956 | 5766.199 |
| `sort_window` | **41.282** | 53.841 | 42.096 | 187.260 | 9780.719 |
| `bloom_filter` | 15.064 | **15.018** | 15.179 | 2483.194 | 7141.594 |
| `hash_join` | **24.518** | 27.395 | 28.025 | 3125.749 | 7101.979 |
| `sieve` | 38.346 | **36.761** | 37.684 | 86.077 | 2903.824 |
| `fib` | 30.831 | 31.544 | **27.318** | 118.660 | 925.758 |
| `collatz` | **15.802** | 16.124 | 16.282 | 64.289 | 583.032 |
| `matmul` | 21.116 | **21.099** | 21.427 | 77.614 | 2595.701 |
| `json_parse` | **7.721** | 8.024 | 9.915 | 32.762 | 34.514 |
| `nbody` | **23.101** | 33.929 | 31.173 | 86.068 | 2198.005 |

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
| _(floor: empty program)_ | _2.647_ | _83.426_ | _**86.073**_ | _56.015_ | _56.436_ | _60.928_ |
| `lcg` | 2.795 | 84.258 | **87.053** | 54.019 | 62.460 | 67.094 |
| `packet_classifier` | 2.793 | 85.004 | **87.797** | 53.911 | 63.171 | 68.421 |
| `ring_write` | 2.868 | 85.237 | **88.105** | 53.995 | 61.803 | 76.924 |
| `histogram_bins` | 2.929 | 104.417 | **107.346** | 54.042 | 64.939 | 72.614 |
| `prefix_scan` | 3.107 | 92.410 | **95.517** | 55.114 | 66.676 | 71.826 |
| `binary_search` | 3.164 | 95.684 | **98.848** | 53.980 | 64.646 | 74.938 |
| `sort_window` | 3.242 | 100.087 | **103.329** | 55.454 | 70.964 | 78.777 |
| `bloom_filter` | 3.452 | 94.788 | **98.240** | 54.794 | 70.756 | 76.472 |
| `hash_join` | 5.693 | 227.916 | **233.609** | 57.915 | 107.984 | 112.648 |
| `sieve` | 3.053 | 90.366 | **93.419** | 54.799 | 71.670 | 78.981 |
| `fib` | 2.757 | 85.642 | **88.399** | 54.468 | 61.770 | 66.374 |
| `collatz` | 2.872 | 88.689 | **91.561** | 54.899 | 64.357 | 70.626 |
| `matmul` | 3.201 | 93.203 | **96.404** | 55.171 | 74.395 | 93.219 |
| `json_parse` | 45.568 | 386.268 | **431.836** | 99.146 | 111.217 | 186.989 |
| `nbody` | 4.300 | 115.774 | **120.074** | 55.320 | 87.582 | 94.127 |

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
