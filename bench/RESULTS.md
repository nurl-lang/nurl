# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T02:46:53Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `61ef913979c02c2fef13b4ff39ac28ef32db2c2f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41161164533 |
| NURL | `v0.81.0-40-g61ef9139` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.1 |
| Python | Python 3.14.4 |

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
| _(floor: empty program)_ | _2.949_ | _2.927_ | _3.031_ | _22.771_ | _12.202_ |
| `lcg` | 36.098 | **35.994** | 36.180 | 1458.962 | 4022.204 |
| `packet_classifier` | 51.230 | **51.200** | 51.349 | 127.713 | 3377.150 |
| `ring_write` | 38.829 | **38.775** | 39.008 | 61.363 | 4888.267 |
| `histogram_bins` | 36.476 | **36.460** | 36.609 | 62.430 | 4481.594 |
| `prefix_scan` | 20.734 | **20.669** | 20.871 | 57.954 | 3353.541 |
| `binary_search` | 33.905 | **31.263** | 35.370 | 90.970 | 5489.755 |
| `sort_window` | **25.039** | 25.048 | 25.214 | 127.505 | 8454.144 |
| `bloom_filter` | **15.265** | 16.254 | 17.773 | 2117.934 | 5710.826 |
| `hash_join` | 22.623 | **22.610** | 25.262 | 2644.537 | 5720.708 |
| `sieve` | 20.759 | **20.302** | 20.650 | 62.213 | 2536.715 |
| `fib` | **23.662** | 27.515 | 27.735 | 117.991 | 837.232 |
| `collatz` | 12.361 | **12.334** | 12.513 | 44.146 | 586.473 |
| `matmul` | **36.993** | 37.087 | 37.725 | 62.282 | 2296.832 |
| `json_parse` | **7.963** | 10.816 | 15.085 | 33.400 | 28.038 |
| `nbody` | **22.021** | 36.755 | 22.617 | 76.979 | 2494.380 |
| `chacha20` | **8.418** | 38.541 | 29.429 | n/a | n/a |
| `poly1305` | **11.513** | 33.063 | 20.261 | n/a | n/a |
| `blake2b` | **40.064** | 56.922 | 62.528 | n/a | n/a |
| `sha512` | 40.393 | **40.261** | 44.123 | n/a | n/a |
| `x25519` | **29.273** | 44.268 | 45.302 | n/a | n/a |

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
| _(floor: empty program)_ | _5.852_ | _103.804_ | _**109.656**_ | _57.275_ | _77.065_ | _55.690_ |
| `lcg` | 6.007 | 109.583 | **115.590** | 56.726 | 79.882 | 62.194 |
| `packet_classifier` | 6.020 | 110.509 | **116.529** | 57.032 | 80.658 | 63.124 |
| `ring_write` | 14.372 | 111.862 | **126.234** | 64.803 | 80.574 | 64.545 |
| `histogram_bins` | 14.551 | 113.444 | **127.995** | 65.743 | 112.508 | 69.990 |
| `prefix_scan` | 14.462 | 113.423 | **127.885** | 64.762 | 84.916 | 67.024 |
| `binary_search` | 14.609 | 112.259 | **126.868** | 65.477 | 82.714 | 68.155 |
| `sort_window` | 14.731 | 114.138 | **128.869** | 65.186 | 89.740 | 73.275 |
| `bloom_filter` | 15.070 | 114.583 | **129.653** | 65.494 | 89.919 | 69.033 |
| `hash_join` | 17.764 | 207.127 | **224.891** | 68.997 | 170.153 | 105.156 |
| `sieve` | 14.500 | 111.892 | **126.392** | 64.855 | 89.546 | 74.072 |
| `fib` | 6.134 | 109.348 | **115.482** | 57.883 | 80.112 | 62.998 |
| `collatz` | 6.189 | 112.161 | **118.350** | 56.885 | 82.066 | 64.418 |
| `matmul` | 15.066 | 113.631 | **128.697** | 66.001 | 91.971 | 80.884 |
| `json_parse` | 40.894 | 345.673 | **386.567** | 92.767 | 129.620 | 146.331 |
| `nbody` | 16.439 | 118.076 | **134.515** | 67.859 | 107.314 | 94.102 |
| `chacha20` | 45.652 | 589.295 | **634.947** | 97.942 | 119.167 | 104.433 |
| `poly1305` | 36.506 | 391.864 | **428.370** | 87.763 | 123.972 | 114.582 |
| `blake2b` | 32.540 | 262.902 | **295.442** | 84.462 | 123.361 | 111.007 |
| `sha512` | 32.435 | 347.471 | **379.906** | 84.328 | 116.947 | 100.839 |
| `x25519` | 43.494 | 1151.138 | **1194.632** | 95.385 | 939.011 | 407.745 |

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
