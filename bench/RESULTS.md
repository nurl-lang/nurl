# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-06T04:49:54Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `0363f419526c715f11aff8516f85aed2a45b87e4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34012287637 |
| NURL | `v0.60.0-8-g0363f419` |
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
| _(floor: empty program)_ | _1.420_ | _1.437_ | _1.618_ | _24.716_ | _16.928_ |
| `lcg` | **39.069** | 39.070 | 39.325 | 2058.044 | 5239.838 |
| `packet_classifier` | **56.216** | 56.334 | 56.566 | 161.810 | 4336.768 |
| `ring_write` | **42.195** | 42.198 | 42.388 | 66.347 | 6439.571 |
| `histogram_bins` | **39.598** | 40.701 | 39.691 | 66.877 | 6096.294 |
| `prefix_scan` | **21.577** | 21.607 | 21.661 | 65.552 | 4532.864 |
| `binary_search` | 39.778 | 38.089 | **37.017** | 107.123 | 6382.727 |
| `sort_window` | **26.558** | 26.608 | 26.705 | 197.363 | 11884.614 |
| `bloom_filter` | **17.803** | 17.828 | 18.339 | 2850.586 | 7654.006 |
| `hash_join` | **26.694** | 27.867 | 29.350 | 3422.117 | 8411.757 |
| `sieve` | 20.228 | 19.828 | **19.821** | 66.783 | 3349.057 |
| `fib` | **25.151** | 29.679 | 25.232 | 131.757 | 1367.742 |
| `collatz` | 12.231 | **12.160** | 12.291 | 48.262 | 721.573 |
| `matmul` | 33.442 | **33.397** | 33.669 | 75.022 | 3318.543 |
| `json_parse` | 9.031 | **8.516** | 11.464 | 35.385 | 39.171 |
| `nbody` | 25.167 | 39.615 | **23.999** | 100.629 | 3088.329 |

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
| _(floor: empty program)_ | _2.635_ | _96.454_ | _**99.089**_ | _58.546_ | _78.393_ | _55.226_ |
| `lcg` | 2.815 | 105.786 | **108.601** | 58.346 | 88.582 | 58.891 |
| `packet_classifier` | 2.908 | 105.787 | **108.695** | 58.015 | 92.902 | 58.459 |
| `ring_write` | 2.983 | 106.256 | **109.239** | 58.189 | 90.381 | 60.305 |
| `histogram_bins` | 3.109 | 119.992 | **123.101** | 60.162 | 109.086 | 68.208 |
| `prefix_scan` | 3.079 | 109.068 | **112.147** | 59.788 | 95.911 | 62.659 |
| `binary_search` | 3.219 | 107.325 | **110.544** | 58.721 | 92.050 | 64.388 |
| `sort_window` | 3.363 | 111.905 | **115.268** | 59.999 | 102.713 | 70.230 |
| `bloom_filter` | 3.561 | 110.825 | **114.386** | 58.837 | 100.468 | 66.448 |
| `hash_join` | 6.073 | 258.743 | **264.816** | 61.865 | 219.290 | 113.705 |
| `sieve` | 3.118 | 108.378 | **111.496** | 59.635 | 100.690 | 68.905 |
| `fib` | 2.828 | 105.489 | **108.317** | 58.726 | 88.738 | 57.884 |
| `collatz` | 2.950 | 108.802 | **111.752** | 59.207 | 89.944 | 61.057 |
| `matmul` | 3.355 | 106.907 | **110.262** | 58.780 | 104.285 | 81.676 |
| `json_parse` | 57.072 | 458.026 | **515.098** | 113.438 | 159.407 | 162.901 |
| `nbody` | 4.743 | 127.092 | **131.835** | 61.464 | 125.431 | 91.006 |

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
