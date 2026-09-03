# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-03T09:35:52Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `fb91142002c5c26d1521c0d58e6cc9db5f9f2a3f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33739303795 |
| NURL | `v0.59.0-2-gfb911420` |
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
| _(floor: empty program)_ | _1.447_ | _1.419_ | _1.623_ | _21.832_ | _16.924_ |
| `lcg` | **39.025** | 39.034 | 39.786 | 2053.483 | 5131.979 |
| `packet_classifier` | **56.089** | 56.241 | 56.301 | 162.280 | 4275.466 |
| `ring_write` | 42.126 | **42.077** | 42.355 | 66.055 | 6212.098 |
| `histogram_bins` | **39.350** | 40.485 | 39.624 | 66.483 | 6076.680 |
| `prefix_scan` | **21.582** | 21.589 | 21.728 | 63.929 | 4415.152 |
| `binary_search` | 39.515 | 38.150 | **36.866** | 105.945 | 6417.581 |
| `sort_window` | **26.520** | 26.556 | 26.652 | 197.305 | 12001.345 |
| `bloom_filter` | **17.774** | 17.836 | 18.315 | 2834.886 | 7493.436 |
| `hash_join` | **26.827** | 27.920 | 29.253 | 3403.793 | 8550.463 |
| `sieve` | 18.321 | **18.179** | 19.826 | 66.282 | 3466.200 |
| `fib` | **25.153** | 29.689 | 25.164 | 131.187 | 1360.861 |
| `collatz` | 12.172 | **12.123** | 12.325 | 49.003 | 709.420 |
| `matmul` | 33.372 | **33.339** | 33.659 | 75.708 | 3105.559 |
| `json_parse` | 8.974 | **8.572** | 11.542 | 33.503 | 37.225 |
| `nbody` | 25.165 | 39.713 | **23.972** | 97.863 | 3071.385 |

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
| _(floor: empty program)_ | _2.709_ | _93.759_ | _**96.468**_ | _58.745_ | _78.706_ | _60.300_ |
| `lcg` | 2.753 | 104.560 | **107.313** | 56.986 | 87.346 | 68.719 |
| `packet_classifier` | 2.853 | 105.803 | **108.656** | 57.708 | 89.102 | 68.999 |
| `ring_write` | 2.934 | 107.128 | **110.062** | 57.994 | 91.652 | 70.026 |
| `histogram_bins` | 3.058 | 115.990 | **119.048** | 57.988 | 106.653 | 76.698 |
| `prefix_scan` | 3.076 | 107.348 | **110.424** | 58.018 | 95.302 | 72.136 |
| `binary_search` | 3.246 | 107.667 | **110.913** | 58.458 | 91.787 | 73.342 |
| `sort_window` | 3.272 | 110.860 | **114.132** | 58.770 | 101.263 | 78.978 |
| `bloom_filter` | 3.521 | 111.521 | **115.042** | 59.444 | 100.549 | 74.800 |
| `hash_join` | 6.052 | 256.224 | **262.276** | 61.691 | 215.244 | 124.743 |
| `sieve` | 3.057 | 107.870 | **110.927** | 58.505 | 100.216 | 78.728 |
| `fib` | 2.856 | 106.543 | **109.399** | 58.743 | 88.457 | 67.452 |
| `collatz` | 2.960 | 108.577 | **111.537** | 58.292 | 90.915 | 69.506 |
| `matmul` | 3.372 | 106.793 | **110.165** | 58.563 | 104.119 | 92.873 |
| `json_parse` | 56.961 | 454.527 | **511.488** | 114.134 | 158.713 | 173.842 |
| `nbody` | 4.715 | 126.067 | **130.782** | 59.467 | 125.578 | 101.594 |

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
