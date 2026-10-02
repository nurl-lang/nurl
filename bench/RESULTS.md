# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-02T19:25:45Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `639fe9ea8e5dc3d7089c456faa00b2ee4e1bb41a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37053499492 |
| NURL | `v0.68.0-11-g639fe9ea` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |
| Node | v22.23.3 |
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
| _(floor: empty program)_ | _1.489_ | _1.424_ | _1.712_ | _24.643_ | _19.792_ |
| `lcg` | 39.245 | **39.244** | 39.458 | 1899.171 | 5179.715 |
| `packet_classifier` | 56.557 | **56.536** | 56.579 | 163.661 | 4378.999 |
| `ring_write` | **42.432** | 42.438 | 42.541 | 68.598 | 6309.839 |
| `histogram_bins` | **39.771** | 40.697 | 41.024 | 67.632 | 6146.122 |
| `prefix_scan` | 21.867 | **21.842** | 22.033 | 67.111 | 4650.505 |
| `binary_search` | 39.825 | **38.524** | 41.190 | 107.463 | 6514.324 |
| `sort_window` | **26.810** | 26.921 | 27.168 | 200.432 | 12987.610 |
| `bloom_filter` | **16.765** | 18.028 | 18.525 | 2857.640 | 7571.958 |
| `hash_join` | **27.338** | 28.073 | 29.493 | 3426.305 | 8264.436 |
| `sieve` | 18.908 | **18.333** | 18.499 | 70.333 | 3263.973 |
| `fib` | **25.306** | 30.109 | 30.289 | 133.636 | 1375.637 |
| `collatz` | 12.528 | **12.407** | 12.745 | 54.239 | 736.450 |
| `matmul` | 34.006 | **33.908** | 34.111 | 80.095 | 3294.443 |
| `json_parse` | 9.612 | **8.985** | 12.463 | 40.248 | 41.767 |
| `nbody` | **25.392** | 39.987 | 25.672 | 104.737 | 3211.008 |

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
| _(floor: empty program)_ | _3.496_ | _103.804_ | _**107.300**_ | _63.508_ | _83.728_ | _56.292_ |
| `lcg` | 3.634 | 118.458 | **122.092** | 62.184 | 93.738 | 59.323 |
| `packet_classifier` | 3.824 | 118.023 | **121.847** | 64.695 | 95.300 | 60.180 |
| `ring_write` | 4.053 | 117.192 | **121.245** | 63.387 | 95.388 | 63.201 |
| `histogram_bins` | 4.041 | 123.360 | **127.401** | 62.939 | 115.548 | 68.951 |
| `prefix_scan` | 4.258 | 117.853 | **122.111** | 64.140 | 102.401 | 64.794 |
| `binary_search` | 4.502 | 118.131 | **122.633** | 65.555 | 99.186 | 66.482 |
| `sort_window` | 4.509 | 119.783 | **124.292** | 64.166 | 108.123 | 70.480 |
| `bloom_filter` | 5.153 | 124.916 | **130.069** | 67.447 | 109.463 | 72.454 |
| `hash_join` | 9.346 | 268.566 | **277.912** | 69.404 | 228.169 | 116.080 |
| `sieve` | 4.302 | 119.366 | **123.668** | 65.969 | 111.672 | 72.391 |
| `fib` | 3.869 | 117.659 | **121.528** | 64.753 | 97.520 | 60.156 |
| `collatz` | 4.193 | 121.575 | **125.768** | 65.867 | 100.082 | 63.436 |
| `matmul` | 4.743 | 119.400 | **124.143** | 65.598 | 113.521 | 82.606 |
| `json_parse` | 108.690 | 478.339 | **587.029** | 170.836 | 174.856 | 170.360 |
| `nbody` | 7.103 | 138.359 | **145.462** | 69.760 | 137.580 | 101.762 |

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
