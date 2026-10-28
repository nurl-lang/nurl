# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T23:35:28Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `290fa03ba94b63bced659a42e01ac0bd6cb3aa57` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40787698049 |
| NURL | `v0.80.0-18-g290fa03b` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v22.23.4 |
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
| Workload scale | ×1 — the published contract (`--scale N` / `BENCH_SCALE=N` multiplies it) |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so a row's cells are timings of the
same computation. **Bold** is the fastest cell in the row; `n/a` is a
language the row is not implemented in (bench/manifest.tsv).

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.550_ | _1.520_ | _1.735_ | _24.258_ | _18.072_ |
| `lcg` | **39.340** | 39.407 | 39.505 | 1817.017 | 5047.307 |
| `packet_classifier` | **56.460** | 56.463 | 56.638 | 163.509 | 4307.543 |
| `ring_write` | **42.419** | 42.458 | 42.605 | 68.674 | 6322.008 |
| `histogram_bins` | **39.783** | 40.940 | 41.071 | 67.725 | 6149.720 |
| `prefix_scan` | **21.821** | 21.892 | 22.152 | 67.367 | 4622.473 |
| `binary_search` | 39.802 | **38.484** | 41.041 | 108.157 | 7273.860 |
| `sort_window` | 26.865 | **26.796** | 26.919 | 198.996 | 11717.424 |
| `bloom_filter` | **16.668** | 17.978 | 18.542 | 2880.016 | 7584.552 |
| `hash_join` | **27.091** | 28.373 | 29.676 | 3470.155 | 8158.954 |
| `sieve` | 23.438 | **22.582** | 22.783 | 72.137 | 3247.064 |
| `fib` | **25.787** | 29.987 | 30.260 | 136.341 | 1349.107 |
| `collatz` | 12.435 | **12.277** | 12.648 | 51.606 | 744.885 |
| `matmul` | 33.799 | **33.670** | 34.005 | 79.468 | 3215.994 |
| `json_parse` | 8.657 | **8.649** | 12.109 | 36.878 | 39.612 |
| `nbody` | **25.366** | 39.979 | 25.715 | 106.157 | 3168.881 |
| `chacha20` | **7.335** | 40.698 | 33.920 | n/a | n/a |
| `poly1305` | **12.023** | 32.121 | 21.477 | n/a | n/a |
| `blake2b` | **44.076** | 65.155 | 69.416 | n/a | n/a |
| `sha512` | **47.593** | 51.027 | 49.748 | n/a | n/a |
| `x25519` | **31.794** | 48.841 | 49.789 | n/a | n/a |

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
| _(floor: empty program)_ | _4.672_ | _121.139_ | _**125.811**_ | _65.590_ | _86.453_ | _63.768_ |
| `lcg` | 4.802 | 134.490 | **139.292** | 65.920 | 96.486 | 73.357 |
| `packet_classifier` | 5.007 | 135.088 | **140.095** | 66.891 | 98.550 | 73.034 |
| `ring_write` | 15.526 | 136.990 | **152.516** | 76.178 | 98.293 | 74.581 |
| `histogram_bins` | 15.652 | 137.866 | **153.518** | 76.612 | 115.484 | 82.271 |
| `prefix_scan` | 15.775 | 138.025 | **153.800** | 76.679 | 102.922 | 76.983 |
| `binary_search` | 15.953 | 137.116 | **153.069** | 76.830 | 100.536 | 80.934 |
| `sort_window` | 16.189 | 137.411 | **153.600** | 75.840 | 109.707 | 84.504 |
| `bloom_filter` | 16.499 | 141.030 | **157.529** | 77.535 | 109.326 | 79.639 |
| `hash_join` | 20.651 | 273.611 | **294.262** | 80.736 | 226.069 | 126.666 |
| `sieve` | 16.172 | 136.114 | **152.286** | 77.811 | 110.464 | 86.443 |
| `fib` | 5.059 | 136.061 | **141.120** | 68.499 | 99.533 | 73.750 |
| `collatz` | 5.196 | 137.810 | **143.006** | 67.322 | 98.329 | 73.006 |
| `matmul` | 17.154 | 137.360 | **154.514** | 77.793 | 112.961 | 95.910 |
| `json_parse` | 51.068 | 499.560 | **550.628** | 112.739 | 167.830 | 183.610 |
| `nbody` | 18.598 | 144.093 | **162.691** | 81.002 | 141.115 | 114.753 |
| `chacha20` | 58.777 | 769.499 | **828.276** | 120.053 | 147.400 | 122.993 |
| `poly1305` | 45.173 | 528.085 | **573.258** | 108.433 | 152.539 | 141.158 |
| `blake2b` | 40.167 | 391.660 | **431.827** | 103.790 | 159.259 | 135.425 |
| `sha512` | 41.062 | 497.996 | **539.058** | 105.652 | 149.076 | 121.842 |
| `x25519` | 53.972 | 1223.928 | **1277.900** | 116.230 | 1246.247 | 522.755 |

## 3. Correctness gate

Each row is timed only when all of its implementations print the same
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
| `chacha20` | `3720502699256473595` | identical across 3 languages |
| `poly1305` | `2498856793803813402` | identical across 3 languages |
| `blake2b` | `8590291023788228918` | identical across 3 languages |
| `sha512` | `7091519178481951668` | identical across 3 languages |
| `x25519` | `6127485567278337128` | identical across 3 languages |

## 4. Reading the numbers

* A cell near the floor row is mostly process start-up, dynamic linking
  and page faults rather than the benchmark. The rows worth comparing are
  the ones in the tens of milliseconds and up.
* All three compiled back ends are LLVM-based and all three are allowed to
  be clever: LLVM will fold an affine recurrence or unroll a loop by a
  different factor in each language. A cell measures optimised throughput
  of the same algorithm, not the source-level iteration count.
* Nine of the original fifteen benchmarks are defined over 64-bit unsigned integers.
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
* `chacha20`, `poly1305`, `blake2b`, `sha512` and `x25519` are NURL / C /
  Rust only. Their NURL file is a driver around the standard library's own
  implementation (stdlib/std/chacha20poly1305.nu, hash_blake2b.nu,
  hash_sha512.nu, x25519.nu) — the row measures the stdlib a NURL program
  actually gets. C and Rust, whose standard libraries have none of the
  five, carry the same formulation written out by hand: Poly1305 at
  radix 2^64 and the donna-c64 X25519 field at radix 2^51, both with
  native 128-bit products. ChaCha20 is the one deliberate difference: C
  and Rust run the scalar RFC rounds, while the stdlib runs it on `v128`
  lanes (`v256` lanes in its x86-64-v3 clone). Each source names its
  RFC/FIPS test vector; x25519 at x1 reproduces RFC 7748's 1000-iteration
  value.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
