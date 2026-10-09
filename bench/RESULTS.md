# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-09T17:14:00Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `d1f4dfb423c11db5fd12ab33b9af67bd25fa7885` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37964137912 |
| NURL | `v0.71.0-13-gd1f4dfb4` |
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
| Workload scale | ×1 — the published contract (`--scale N` / `BENCH_SCALE=N` multiplies it) |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so a row's cells are timings of the
same computation. **Bold** is the fastest cell in the row; `n/a` is a
language the row is not implemented in (bench/manifest.tsv).

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.464_ | _1.449_ | _1.662_ | _23.424_ | _18.360_ |
| `lcg` | 39.266 | **39.166** | 39.398 | 1897.740 | 5098.450 |
| `packet_classifier` | 56.479 | **56.472** | 56.565 | 163.615 | 4378.891 |
| `ring_write` | **42.311** | 42.334 | 42.468 | 67.450 | 6501.718 |
| `histogram_bins` | **39.662** | 40.573 | 40.754 | 68.157 | 6278.480 |
| `prefix_scan` | **21.697** | 21.783 | 21.877 | 68.324 | 4469.140 |
| `binary_search` | 39.495 | **38.292** | 41.240 | 108.994 | 6166.976 |
| `sort_window` | **26.653** | 26.723 | 26.898 | 198.388 | 11571.408 |
| `bloom_filter` | **15.409** | 17.957 | 18.517 | 2832.470 | 7653.675 |
| `hash_join` | **26.762** | 28.263 | 29.510 | 3403.416 | 8098.287 |
| `sieve` | 21.023 | **20.623** | 20.783 | 68.924 | 3201.198 |
| `fib` | **25.387** | 29.996 | 30.341 | 133.909 | 1367.980 |
| `collatz` | 12.535 | **12.492** | 12.700 | 53.155 | 748.557 |
| `matmul` | 33.933 | **33.814** | 34.277 | 79.936 | 3091.719 |
| `json_parse` | **8.603** | 9.074 | 12.320 | 38.736 | 41.062 |
| `nbody` | **25.482** | 39.948 | 26.625 | 102.477 | 3142.538 |
| `chacha20` | **7.706** | 42.270 | 33.962 | n/a | n/a |
| `poly1305` | 23.736 | 32.015 | **21.514** | n/a | n/a |
| `blake2b` | **44.194** | 65.241 | 69.439 | n/a | n/a |
| `sha512` | **47.634** | 50.800 | 50.009 | n/a | n/a |
| `x25519` | **44.723** | 48.911 | 49.720 | n/a | n/a |

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
| _(floor: empty program)_ | _4.053_ | _102.330_ | _**106.383**_ | _61.757_ | _81.863_ | _68.712_ |
| `lcg` | 4.022 | 115.934 | **119.956** | 62.589 | 92.075 | 70.375 |
| `packet_classifier` | 4.077 | 113.382 | **117.459** | 61.282 | 90.682 | 70.460 |
| `ring_write` | 4.339 | 117.435 | **121.774** | 64.330 | 97.812 | 74.165 |
| `histogram_bins` | 4.394 | 123.024 | **127.418** | 62.457 | 112.458 | 83.645 |
| `prefix_scan` | 4.480 | 115.051 | **119.531** | 62.103 | 97.653 | 74.768 |
| `binary_search` | 4.786 | 117.103 | **121.889** | 64.494 | 96.083 | 77.726 |
| `sort_window` | 5.021 | 119.743 | **124.764** | 63.450 | 105.162 | 82.673 |
| `bloom_filter` | 5.672 | 124.768 | **130.440** | 67.597 | 109.810 | 80.416 |
| `hash_join` | 9.699 | 265.987 | **275.686** | 66.813 | 220.735 | 124.808 |
| `sieve` | 4.954 | 116.998 | **121.952** | 64.248 | 107.112 | 84.102 |
| `fib` | 4.562 | 121.946 | **126.508** | 66.345 | 95.368 | 72.795 |
| `collatz` | 4.627 | 128.002 | **132.629** | 67.563 | 100.896 | 77.087 |
| `matmul` | 6.703 | 123.467 | **130.170** | 70.719 | 113.405 | 95.511 |
| `json_parse` | 53.947 | 505.580 | **559.527** | 117.340 | 170.809 | 178.551 |
| `nbody` | 7.919 | 140.535 | **148.454** | 70.662 | 134.219 | 114.509 |
| `chacha20` | 56.990 | 627.918 | **684.908** | 118.425 | 145.608 | 123.006 |
| `poly1305` | 37.397 | 267.090 | **304.487** | 99.366 | 152.336 | 136.767 |
| `blake2b` | 39.164 | 369.342 | **408.506** | 100.308 | 152.172 | 133.772 |
| `sha512` | 39.782 | 490.278 | **530.060** | 102.402 | 148.187 | 122.741 |
| `x25519` | 49.340 | 748.245 | **797.585** | 111.758 | 1265.979 | 520.770 |

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
  five, carry the same formulation written out by hand: poly1305-donna-64
  and the donna-c64 X25519 field with native 128-bit products, scalar
  ChaCha20 (the stdlib runs it on `v128` lanes). Each source names its
  RFC/FIPS test vector; x25519 at x1 reproduces RFC 7748's 1000-iteration
  value.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
