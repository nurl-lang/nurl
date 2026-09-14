# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-14T11:20:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `48ed49a6e59da3e676d1a0e834f6d8120d6ba154` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34837275185 |
| NURL | `v0.65.0-12-g48ed49a6` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.1 (48a229cea 2026-09-01) |
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
| _(floor: empty program)_ | _1.449_ | _1.456_ | _1.637_ | _22.306_ | _16.974_ |
| `lcg` | **39.144** | 39.170 | 39.429 | 2059.744 | 5107.995 |
| `packet_classifier` | 56.394 | **56.344** | 56.643 | 165.368 | 4367.221 |
| `ring_write` | 42.506 | **42.388** | 42.657 | 68.095 | 6441.849 |
| `histogram_bins` | **39.789** | 40.841 | 39.866 | 66.758 | 6226.199 |
| `prefix_scan` | 21.859 | **21.833** | 21.856 | 65.681 | 4492.746 |
| `binary_search` | 39.774 | 38.453 | **37.350** | 107.257 | 6479.570 |
| `sort_window` | **26.737** | 26.770 | 26.951 | 198.852 | 12341.884 |
| `bloom_filter` | **16.654** | 17.854 | 18.437 | 2854.849 | 7665.755 |
| `hash_join` | **27.310** | 28.132 | 29.534 | 3433.574 | 8386.808 |
| `sieve` | 20.324 | 19.595 | **19.126** | 69.230 | 3310.427 |
| `fib` | **25.374** | 30.008 | 25.548 | 132.705 | 1376.524 |
| `collatz` | **12.282** | 12.295 | 12.605 | 52.582 | 724.316 |
| `matmul` | 33.582 | **33.492** | 34.048 | 77.543 | 3124.549 |
| `json_parse` | 9.826 | **8.627** | 11.387 | 37.807 | 40.903 |
| `nbody` | 25.387 | 39.948 | **24.277** | 104.324 | 3089.278 |

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
| _(floor: empty program)_ | _3.180_ | _97.192_ | _**100.372**_ | _61.712_ | _81.258_ | _60.327_ |
| `lcg` | 3.408 | 108.279 | **111.687** | 59.814 | 89.722 | 73.008 |
| `packet_classifier` | 3.637 | 113.362 | **116.999** | 61.926 | 93.833 | 71.476 |
| `ring_write` | 3.907 | 116.467 | **120.374** | 63.577 | 95.412 | 72.993 |
| `histogram_bins` | 4.011 | 119.633 | **123.644** | 60.933 | 109.369 | 78.404 |
| `prefix_scan` | 4.083 | 115.529 | **119.612** | 61.844 | 100.392 | 74.797 |
| `binary_search` | 4.423 | 114.423 | **118.846** | 63.979 | 97.650 | 77.665 |
| `sort_window` | 4.451 | 119.361 | **123.812** | 64.348 | 107.989 | 82.608 |
| `bloom_filter` | 4.869 | 117.435 | **122.304** | 64.227 | 108.331 | 80.980 |
| `hash_join` | 9.413 | 263.743 | **273.156** | 68.087 | 224.144 | 126.955 |
| `sieve` | 4.200 | 116.839 | **121.039** | 64.809 | 108.749 | 87.863 |
| `fib` | 3.728 | 114.439 | **118.167** | 63.171 | 96.723 | 72.532 |
| `collatz` | 3.996 | 115.380 | **119.376** | 63.013 | 95.642 | 74.025 |
| `matmul` | 4.523 | 114.045 | **118.568** | 63.382 | 110.592 | 99.558 |
| `json_parse` | 106.888 | 492.896 | **599.784** | 166.100 | 165.745 | 177.992 |
| `nbody` | 6.559 | 133.129 | **139.688** | 65.832 | 132.458 | 111.083 |

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
