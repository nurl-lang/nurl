# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T09:51:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `2d95263bea9054b6b1f4812165693b11ceea1674` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40666709226 |
| NURL | `v0.79.1-35-g2d95263b` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
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
| Workload scale | ×1 — the published contract (`--scale N` / `BENCH_SCALE=N` multiplies it) |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so a row's cells are timings of the
same computation. **Bold** is the fastest cell in the row; `n/a` is a
language the row is not implemented in (bench/manifest.tsv).

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.474_ | _1.469_ | _1.699_ | _24.116_ | _17.218_ |
| `lcg` | 39.162 | **39.143** | 39.279 | 1894.234 | 5056.844 |
| `packet_classifier` | 56.442 | **56.297** | 56.492 | 162.317 | 4546.946 |
| `ring_write` | 42.262 | **42.187** | 42.405 | 65.561 | 6508.444 |
| `histogram_bins` | **39.464** | 40.600 | 40.872 | 67.519 | 6051.479 |
| `prefix_scan` | 21.747 | **21.669** | 21.949 | 66.436 | 4566.479 |
| `binary_search` | 39.768 | **38.306** | 40.936 | 106.697 | 6378.417 |
| `sort_window` | 26.633 | **26.537** | 26.814 | 198.361 | 11372.552 |
| `bloom_filter` | **16.652** | 17.921 | 18.466 | 2842.899 | 7412.206 |
| `hash_join` | **26.849** | 27.875 | 29.257 | 3471.128 | 8430.027 |
| `sieve` | 18.775 | **18.125** | 18.133 | 65.959 | 3333.093 |
| `fib` | **25.066** | 29.765 | 29.829 | 130.652 | 1360.716 |
| `collatz` | 12.410 | **12.209** | 12.588 | 51.173 | 738.956 |
| `matmul` | 33.535 | **33.422** | 33.657 | 76.151 | 3285.046 |
| `json_parse` | **8.398** | 8.562 | 11.820 | 34.068 | 38.454 |
| `nbody` | 25.386 | 39.660 | **25.190** | 102.560 | 3092.444 |
| `chacha20` | **7.356** | 42.442 | 33.762 | n/a | n/a |
| `poly1305` | **11.643** | 31.731 | 21.160 | n/a | n/a |
| `blake2b` | **43.661** | 64.941 | 69.059 | n/a | n/a |
| `sha512` | **47.299** | 50.596 | 49.534 | n/a | n/a |
| `x25519` | **31.386** | 48.832 | 49.266 | n/a | n/a |

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
| _(floor: empty program)_ | _4.558_ | _113.310_ | _**117.868**_ | _61.830_ | _77.581_ | _53.852_ |
| `lcg` | 4.754 | 127.142 | **131.896** | 62.074 | 89.047 | 56.494 |
| `packet_classifier` | 4.701 | 127.149 | **131.850** | 62.674 | 92.109 | 58.272 |
| `ring_write` | 15.476 | 129.077 | **144.553** | 71.460 | 90.998 | 59.351 |
| `histogram_bins` | 15.127 | 130.301 | **145.428** | 71.690 | 107.459 | 68.529 |
| `prefix_scan` | 15.239 | 129.719 | **144.958** | 72.415 | 97.588 | 64.017 |
| `binary_search` | 15.544 | 129.120 | **144.664** | 71.866 | 92.479 | 65.459 |
| `sort_window` | 15.881 | 130.893 | **146.774** | 71.760 | 102.065 | 69.091 |
| `bloom_filter` | 16.264 | 134.670 | **150.934** | 73.520 | 104.353 | 65.832 |
| `hash_join` | 19.750 | 263.146 | **282.896** | 75.794 | 218.648 | 109.026 |
| `sieve` | 15.720 | 130.821 | **146.541** | 72.702 | 103.934 | 70.218 |
| `fib` | 4.713 | 125.662 | **130.375** | 61.954 | 89.494 | 58.503 |
| `collatz` | 5.018 | 131.857 | **136.875** | 64.400 | 93.137 | 60.008 |
| `matmul` | 17.041 | 129.265 | **146.306** | 73.860 | 104.436 | 77.680 |
| `json_parse` | 49.908 | 488.875 | **538.783** | 106.918 | 159.136 | 154.562 |
| `nbody` | 18.204 | 134.877 | **153.081** | 73.905 | 126.407 | 93.064 |
| `chacha20` | 58.832 | 782.158 | **840.990** | 117.349 | 142.271 | 105.633 |
| `poly1305` | 44.766 | 511.510 | **556.276** | 102.640 | 142.824 | 118.506 |
| `blake2b` | 39.148 | 376.070 | **415.218** | 94.919 | 145.603 | 113.961 |
| `sha512` | 39.480 | 472.503 | **511.983** | 95.839 | 137.434 | 100.024 |
| `x25519` | 52.656 | 1193.818 | **1246.474** | 108.811 | 1217.422 | 491.259 |

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
