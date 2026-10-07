# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-07T03:41:43Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372432 KiB |
| Commit | `efe80836c2aa6dbc065dcf761ebaa5d364b67824` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37567582945 |
| NURL | `v0.70.0-22-gefe80836` |
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
| _(floor: empty program)_ | _1.143_ | _1.128_ | _1.257_ | _17.915_ | _12.076_ |
| `lcg` | **30.814** | 30.957 | 31.101 | 1093.405 | 3079.935 |
| `packet_classifier` | **53.502** | 53.508 | 53.824 | 130.707 | 2580.867 |
| `ring_write` | 33.724 | 33.803 | **33.586** | 52.429 | 3700.926 |
| `histogram_bins` | 31.380 | **31.331** | 31.589 | 52.830 | 3676.099 |
| `prefix_scan` | 19.607 | **18.743** | 19.562 | 53.494 | 2630.133 |
| `binary_search` | 27.697 | **22.613** | 29.794 | 87.279 | 4230.774 |
| `sort_window` | 31.467 | **31.105** | 31.802 | 141.585 | 7938.826 |
| `bloom_filter` | **10.872** | 11.058 | 11.223 | 1880.360 | 5141.760 |
| `hash_join` | **18.548** | 19.386 | 19.886 | 2312.805 | 5561.185 |
| `sieve` | 35.719 | **34.302** | 34.481 | 74.371 | 2211.982 |
| `fib` | **17.925** | 21.087 | 21.424 | 88.403 | 693.326 |
| `collatz` | **11.545** | 11.729 | 12.742 | 48.513 | 451.565 |
| `matmul` | 15.426 | **15.213** | 15.508 | 59.405 | 2094.220 |
| `json_parse` | **5.486** | 6.174 | 7.358 | 26.111 | 26.620 |
| `nbody` | **16.891** | 23.550 | 17.121 | 65.401 | 1652.686 |

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
| _(floor: empty program)_ | _2.911_ | _73.925_ | _**76.836**_ | _46.225_ | _60.497_ | _46.157_ |
| `lcg` | 2.872 | 81.409 | **84.281** | 46.212 | 67.383 | 50.201 |
| `packet_classifier` | 2.871 | 79.083 | **81.954** | 44.793 | 72.453 | 50.210 |
| `ring_write` | 3.238 | 83.369 | **86.607** | 46.639 | 68.509 | 52.090 |
| `histogram_bins` | 3.281 | 86.355 | **89.636** | 45.441 | 78.309 | 54.168 |
| `prefix_scan` | 3.301 | 81.174 | **84.475** | 43.879 | 69.547 | 54.194 |
| `binary_search` | 3.373 | 82.171 | **85.544** | 45.514 | 67.160 | 56.794 |
| `sort_window` | 3.705 | 86.647 | **90.352** | 47.620 | 76.402 | 59.480 |
| `bloom_filter` | 4.099 | 88.460 | **92.559** | 49.134 | 77.712 | 58.884 |
| `hash_join` | 6.491 | 175.813 | **182.304** | 48.629 | 144.772 | 88.055 |
| `sieve` | 3.189 | 83.225 | **86.414** | 46.942 | 75.496 | 59.738 |
| `fib` | 3.210 | 86.314 | **89.524** | 48.658 | 69.042 | 50.317 |
| `collatz` | 3.208 | 85.775 | **88.983** | 48.202 | 75.398 | 56.111 |
| `matmul` | 3.653 | 85.716 | **89.369** | 47.745 | 80.645 | 68.936 |
| `json_parse` | 32.929 | 305.726 | **338.655** | 77.720 | 114.555 | 131.856 |
| `nbody` | 5.026 | 99.498 | **104.524** | 49.938 | 91.410 | 78.766 |

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
