# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-26T20:42:39Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `b2b2ac59538994d4a40af1c151bd17af4a4d88a8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33011365191 |
| NURL | `v0.53.0` |
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
| _(floor: empty program)_ | _1.423_ | _1.412_ | _1.642_ | _22.872_ | _16.894_ |
| `lcg` | 39.231 | **39.115** | 39.294 | 2043.491 | 5183.869 |
| `packet_classifier` | 56.278 | **56.163** | 56.469 | 162.335 | 4365.711 |
| `ring_write` | **42.140** | 42.259 | 42.544 | 68.027 | 6042.761 |
| `histogram_bins` | **39.596** | 40.577 | 39.786 | 66.609 | 6268.838 |
| `prefix_scan` | 21.743 | **21.629** | 21.676 | 65.986 | 4556.395 |
| `binary_search` | **36.150** | 38.312 | 36.932 | 106.210 | 5960.597 |
| `sort_window` | 26.629 | **26.559** | 26.819 | 197.674 | 11556.638 |
| `bloom_filter` | 17.895 | **17.753** | 18.245 | 2853.135 | 7552.949 |
| `hash_join` | **27.545** | 27.938 | 29.218 | 3428.141 | 8514.264 |
| `sieve` | 19.978 | **19.589** | 20.151 | 67.302 | 3457.264 |
| `fib` | **25.118** | 29.722 | 25.313 | 131.783 | 1349.217 |
| `collatz` | 12.265 | **12.152** | 12.296 | 50.919 | 715.427 |
| `matmul` | 33.580 | **33.417** | 33.686 | 75.351 | 3091.597 |
| `json_parse` | 8.863 | **8.453** | 11.649 | 36.796 | 37.422 |
| `nbody` | 25.100 | 39.633 | **24.207** | 102.593 | 3015.001 |

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
| _(floor: empty program)_ | _2.603_ | _91.964_ | _**94.567**_ | _58.747_ | _78.397_ | _53.780_ |
| `lcg` | 2.760 | 94.092 | **96.852** | 56.910 | 89.085 | 58.769 |
| `packet_classifier` | 2.816 | 94.861 | **97.677** | 57.875 | 90.361 | 59.228 |
| `ring_write` | 2.975 | 96.577 | **99.552** | 58.787 | 92.778 | 60.453 |
| `histogram_bins` | 2.984 | 113.337 | **116.321** | 57.462 | 106.352 | 68.185 |
| `prefix_scan` | 3.036 | 97.759 | **100.795** | 57.747 | 96.836 | 63.952 |
| `binary_search` | 3.213 | 101.481 | **104.694** | 58.243 | 91.419 | 65.958 |
| `sort_window` | 3.272 | 104.329 | **107.601** | 58.861 | 101.730 | 70.666 |
| `bloom_filter` | 3.470 | 101.503 | **104.973** | 58.537 | 100.501 | 66.975 |
| `hash_join` | 5.963 | 256.422 | **262.385** | 61.170 | 216.467 | 112.971 |
| `sieve` | 3.067 | 99.173 | **102.240** | 58.993 | 102.082 | 69.644 |
| `fib` | 2.965 | 97.777 | **100.742** | 57.593 | 88.305 | 58.648 |
| `collatz` | 2.939 | 96.304 | **99.243** | 58.201 | 91.687 | 61.193 |
| `matmul` | 3.347 | 100.487 | **103.834** | 58.797 | 105.040 | 82.787 |
| `json_parse` | 52.921 | 427.136 | **480.057** | 109.400 | 158.998 | 163.919 |
| `nbody` | 4.616 | 125.079 | **129.695** | 60.313 | 126.430 | 91.949 |

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
