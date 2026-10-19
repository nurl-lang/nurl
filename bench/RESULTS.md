# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-19T09:44:35Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `2d278f3110ce27bdddfe67e4d77f51a8473ece89` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39231601063 |
| NURL | `v0.73.0-8-g2d278f31` |
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
| _(floor: empty program)_ | _1.563_ | _1.546_ | _1.783_ | _24.482_ | _17.808_ |
| `lcg` | 44.044 | **44.038** | 44.243 | 1817.066 | 5356.215 |
| `packet_classifier` | **63.526** | 63.539 | 63.691 | 157.710 | 4568.981 |
| `ring_write` | 47.590 | **47.557** | 47.799 | 73.114 | 6529.776 |
| `histogram_bins` | **44.486** | 44.529 | 44.704 | 74.611 | 6259.286 |
| `prefix_scan` | 24.401 | **24.368** | 24.679 | 70.569 | 4644.545 |
| `binary_search` | 41.466 | **35.804** | 43.394 | 111.173 | 6269.905 |
| `sort_window` | 29.944 | **29.917** | 30.179 | 168.789 | 12161.902 |
| `bloom_filter` | **17.298** | 18.718 | 20.626 | 2721.510 | 8004.572 |
| `hash_join` | **27.564** | 28.594 | 30.163 | 3439.426 | 9015.933 |
| `sieve` | 20.468 | **20.101** | 20.172 | 71.890 | 3500.244 |
| `fib` | **27.875** | 33.169 | 33.360 | 143.133 | 1301.283 |
| `collatz` | **13.618** | 13.658 | 13.892 | 51.426 | 749.156 |
| `matmul` | **45.492** | 45.984 | 45.807 | 84.046 | 3544.682 |
| `json_parse` | **7.843** | 8.853 | 12.058 | 38.026 | 39.277 |
| `nbody` | **26.714** | 45.036 | 26.854 | 95.048 | 3203.458 |
| `chacha20` | **8.974** | 45.912 | 35.594 | n/a | n/a |
| `poly1305` | 26.241 | 40.177 | **23.778** | n/a | n/a |
| `blake2b` | **48.375** | 71.479 | 78.285 | n/a | n/a |
| `sha512` | **49.708** | 51.673 | 54.490 | n/a | n/a |
| `x25519` | **49.176** | 53.974 | 55.802 | n/a | n/a |

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
| _(floor: empty program)_ | _4.443_ | _105.855_ | _**110.298**_ | _65.619_ | _86.009_ | _56.891_ |
| `lcg` | 4.648 | 117.769 | **122.417** | 65.748 | 94.354 | 60.674 |
| `packet_classifier` | 4.741 | 117.904 | **122.645** | 65.556 | 96.527 | 61.602 |
| `ring_write` | 13.800 | 123.361 | **137.161** | 75.451 | 97.114 | 63.430 |
| `histogram_bins` | 13.780 | 129.724 | **143.504** | 76.329 | 114.002 | 70.873 |
| `prefix_scan` | 13.929 | 124.348 | **138.277** | 76.119 | 102.903 | 66.726 |
| `binary_search` | 13.970 | 122.986 | **136.956** | 76.201 | 98.714 | 67.783 |
| `sort_window` | 14.007 | 125.759 | **139.766** | 76.079 | 107.872 | 72.124 |
| `bloom_filter` | 14.617 | 126.082 | **140.699** | 76.654 | 106.260 | 68.591 |
| `hash_join` | 18.093 | 260.715 | **278.808** | 80.286 | 213.599 | 113.172 |
| `sieve` | 14.005 | 123.155 | **137.160** | 77.554 | 108.529 | 73.030 |
| `fib` | 4.896 | 118.417 | **123.313** | 66.327 | 95.460 | 61.791 |
| `collatz` | 4.958 | 121.320 | **126.278** | 66.551 | 96.714 | 62.284 |
| `matmul` | 15.594 | 123.769 | **139.363** | 77.690 | 110.243 | 81.982 |
| `json_parse` | 45.302 | 467.875 | **513.177** | 108.700 | 160.872 | 159.382 |
| `nbody` | 16.513 | 141.568 | **158.081** | 78.537 | 130.401 | 97.814 |
| `chacha20` | 46.379 | 753.488 | **799.867** | 108.241 | 142.832 | 108.535 |
| `poly1305` | 31.288 | 267.042 | **298.330** | 93.496 | 144.787 | 122.991 |
| `blake2b` | 35.195 | 375.938 | **411.133** | 97.358 | 149.575 | 118.812 |
| `sha512` | 35.374 | 461.372 | **496.746** | 98.033 | 141.988 | 103.984 |
| `x25519` | 39.187 | 696.452 | **735.639** | 101.504 | 1194.334 | 496.759 |

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
