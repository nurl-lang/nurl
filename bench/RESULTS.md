# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-05T12:09:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `545b5ed61aedbeca08a0669c41b1f1166c88261c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42023862422 |
| NURL | `v0.87.0` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.2 |
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
| _(floor: empty program)_ | _3.619_ | _3.571_ | _3.632_ | _28.484_ | _15.225_ |
| `lcg` | 40.975 | **40.912** | 41.144 | 1812.356 | 4846.479 |
| `packet_classifier` | 59.061 | **58.774** | 58.935 | 168.238 | 4038.565 |
| `ring_write` | 44.343 | **44.212** | 44.424 | 69.565 | 6281.082 |
| `histogram_bins` | **41.436** | 42.535 | 42.678 | 69.540 | 5808.108 |
| `prefix_scan` | 23.596 | **23.524** | 23.778 | 68.177 | 4218.335 |
| `binary_search` | 41.641 | **40.105** | 42.863 | 108.220 | 8845.836 |
| `sort_window` | **28.496** | 28.553 | 28.780 | 196.790 | 11843.449 |
| `bloom_filter` | **18.682** | 19.679 | 20.268 | 2796.667 | 7020.533 |
| `hash_join` | 29.070 | **28.410** | 31.245 | 3384.190 | 7691.650 |
| `sieve` | 25.967 | **23.754** | 23.849 | 72.688 | 3075.698 |
| `fib` | **27.197** | 31.728 | 31.987 | 134.566 | 1137.298 |
| `collatz` | 14.131 | **14.085** | 14.719 | 54.498 | 701.721 |
| `matmul` | 35.451 | **35.282** | 35.654 | 73.529 | 2864.140 |
| `json_parse` | **8.089** | 12.990 | 18.149 | 38.983 | 36.687 |
| `nbody` | **26.266** | 42.060 | 27.539 | 104.542 | 3151.994 |
| `chacha20` | **9.619** | 43.104 | 35.835 | n/a | n/a |
| `poly1305` | **13.498** | 33.818 | 23.140 | n/a | n/a |
| `blake2b` | **45.949** | 66.889 | 71.393 | n/a | n/a |
| `sha512` | **49.457** | 49.907 | 51.474 | n/a | n/a |
| `x25519` | **34.490** | 50.993 | 51.589 | n/a | n/a |

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
| _(floor: empty program)_ | _7.027_ | _126.739_ | _**133.766**_ | _69.930_ | _83.764_ | _66.584_ |
| `lcg` | 6.946 | 132.969 | **139.915** | 65.149 | 92.815 | 70.528 |
| `packet_classifier` | 7.137 | 134.934 | **142.071** | 65.074 | 92.504 | 72.482 |
| `ring_write` | 15.542 | 135.403 | **150.945** | 72.827 | 92.541 | 73.682 |
| `histogram_bins` | 15.523 | 135.013 | **150.536** | 72.270 | 135.124 | 80.932 |
| `prefix_scan` | 15.420 | 133.643 | **149.063** | 71.589 | 97.599 | 77.867 |
| `binary_search` | 15.578 | 133.511 | **149.089** | 72.138 | 92.438 | 79.739 |
| `sort_window` | 15.832 | 135.223 | **151.055** | 72.248 | 102.491 | 83.201 |
| `bloom_filter` | 16.179 | 137.592 | **153.771** | 74.110 | 102.282 | 80.659 |
| `hash_join` | 19.451 | 266.626 | **286.077** | 75.912 | 216.435 | 125.009 |
| `sieve` | 15.824 | 132.705 | **148.529** | 72.202 | 103.246 | 85.021 |
| `fib` | 7.053 | 129.986 | **137.039** | 63.039 | 89.194 | 72.087 |
| `collatz` | 7.298 | 135.822 | **143.120** | 64.790 | 91.845 | 73.282 |
| `matmul` | 15.985 | 137.601 | **153.586** | 74.015 | 108.833 | 96.952 |
| `json_parse` | 45.520 | 338.857 | **384.377** | 102.887 | 159.364 | 176.356 |
| `nbody` | 17.270 | 142.520 | **159.790** | 74.970 | 128.437 | 110.740 |
| `chacha20` | 66.411 | 689.146 | **755.557** | 124.936 | 144.370 | 127.388 |
| `poly1305` | 55.060 | 422.552 | **477.612** | 114.360 | 149.694 | 139.495 |
| `blake2b` | 36.542 | 342.148 | **378.690** | 95.867 | 147.523 | 147.965 |
| `sha512` | 35.355 | 455.919 | **491.274** | 93.876 | 141.311 | 118.979 |
| `x25519` | 50.596 | 1393.065 | **1443.661** | 108.283 | 1238.264 | 511.677 |

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
