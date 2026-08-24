# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-24T21:03:33Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `729673d10fdbe04cd4bd4b206cf07392708d529e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32776940650 |
| NURL | `v0.51.0` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |
| Node | v22.23.2 |
| Python | Python 3.12.3 |

| Setting | Value |
|---|---|
| NURL flags | `nurlc` → LLVM IR; `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` (ThinLTO backend at O3 — the standard `nurl.sh` release pipeline) |
| C flags | `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` — the identical pipeline, so neither column gets a backend the other lacks |
| Rust flags | `rustc -C opt-level=3` — rustc has no prelink/backend split; opt-level 3 is the `cargo build --release` default |
| Node / Python | `node` / `python3`, no flags |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.452_ | _1.430_ | _1.685_ | _22.016_ | _17.342_ |
| `lcg` | 38.995 | **38.931** | 39.126 | 2048.885 | 5577.824 |
| `packet_classifier` | 56.214 | **56.133** | 56.386 | 161.645 | 4691.622 |
| `ring_write` | 42.281 | **42.214** | 42.412 | 66.341 | 6395.469 |
| `histogram_bins` | **39.399** | 40.457 | 39.543 | 67.649 | 6018.080 |
| `prefix_scan` | 21.720 | **21.595** | 21.663 | 64.866 | 4584.836 |
| `binary_search` | **36.286** | 37.980 | 37.085 | 107.075 | 6387.939 |
| `sort_window` | 26.493 | **26.455** | 26.638 | 197.921 | 13865.814 |
| `bloom_filter` | 17.834 | **17.794** | 18.300 | 2843.970 | 7719.949 |
| `hash_join` | **26.711** | 27.768 | 29.133 | 3402.562 | 8454.840 |
| `sieve` | 20.147 | 17.802 | **17.736** | 65.999 | 3256.502 |
| `fib` | **25.021** | 29.693 | 25.194 | 131.291 | 1382.169 |
| `collatz` | 12.237 | **12.127** | 12.366 | 48.679 | 717.858 |
| `matmul` | 33.431 | **33.352** | 33.565 | 74.670 | 3463.305 |
| `json_parse` | 8.897 | **8.561** | 11.626 | 36.265 | 37.472 |
| `nbody` | 25.209 | 39.593 | **24.059** | 100.596 | 3047.954 |

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
| _(floor: empty program)_ | _2.736_ | _94.803_ | _**97.539**_ | _58.965_ | _77.338_ | _56.479_ |
| `lcg` | 2.807 | 94.616 | **97.423** | 57.727 | 88.946 | 60.812 |
| `packet_classifier` | 2.897 | 95.219 | **98.116** | 58.360 | 90.865 | 60.353 |
| `ring_write` | 3.005 | 95.813 | **98.818** | 58.459 | 91.160 | 62.653 |
| `histogram_bins` | 3.152 | 113.860 | **117.012** | 58.357 | 107.857 | 69.810 |
| `prefix_scan` | 3.107 | 97.802 | **100.909** | 58.189 | 96.586 | 65.476 |
| `binary_search` | 3.279 | 103.874 | **107.153** | 58.543 | 93.263 | 66.662 |
| `sort_window` | 3.330 | 105.634 | **108.964** | 58.391 | 102.043 | 72.362 |
| `bloom_filter` | 3.587 | 102.114 | **105.701** | 58.645 | 100.829 | 68.541 |
| `hash_join` | 5.975 | 254.433 | **260.408** | 60.913 | 217.117 | 114.501 |
| `sieve` | 3.119 | 97.743 | **100.862** | 58.439 | 103.034 | 72.235 |
| `fib` | 2.874 | 95.862 | **98.736** | 58.507 | 89.150 | 60.881 |
| `collatz` | 3.009 | 96.964 | **99.973** | 58.354 | 90.269 | 61.943 |
| `matmul` | 3.352 | 99.909 | **103.261** | 58.686 | 104.261 | 84.335 |
| `json_parse` | 51.699 | 432.039 | **483.738** | 108.404 | 160.055 | 165.069 |
| `nbody` | 4.668 | 124.825 | **129.493** | 59.872 | 127.052 | 94.005 |

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
