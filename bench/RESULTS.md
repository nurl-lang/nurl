# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T21:07:22Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `52916e5494199b99b34d0215034638676b33ffff` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40954192006 |
| NURL | `v0.80.0-79-g52916e54` |
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
| _(floor: empty program)_ | _1.277_ | _1.248_ | _1.427_ | _20.958_ | _14.305_ |
| `lcg` | 34.485 | **34.337** | 34.530 | 1418.852 | 4216.164 |
| `packet_classifier` | 49.477 | **49.425** | 49.618 | 122.885 | 3526.651 |
| `ring_write` | **37.025** | 37.065 | 37.319 | 58.383 | 5291.186 |
| `histogram_bins` | 34.801 | **34.744** | 34.896 | 60.519 | 4890.984 |
| `prefix_scan` | 19.226 | **19.176** | 19.331 | 59.106 | 3602.090 |
| `binary_search` | 32.465 | **27.695** | 33.658 | 88.615 | 4882.548 |
| `sort_window` | 23.433 | **23.432** | 23.605 | 130.723 | 8886.617 |
| `bloom_filter` | **13.652** | 14.765 | 16.335 | 2180.694 | 6274.922 |
| `hash_join` | **21.727** | 22.379 | 23.671 | 2637.535 | 6324.399 |
| `sieve` | 20.005 | **19.212** | 19.681 | 61.191 | 2841.745 |
| `fib` | **21.803** | 25.895 | 26.199 | 113.230 | 1013.714 |
| `collatz` | 10.802 | **10.747** | 10.944 | 43.177 | 585.234 |
| `matmul` | 35.288 | **34.887** | 35.365 | 67.438 | 2701.462 |
| `json_parse` | **6.440** | 7.031 | 9.590 | 33.564 | 32.189 |
| `nbody` | **21.052** | 35.081 | 21.085 | 78.526 | 2556.693 |
| `chacha20` | **6.801** | 35.939 | 27.883 | n/a | n/a |
| `poly1305` | **10.207** | 31.408 | 18.837 | n/a | n/a |
| `blake2b` | **38.302** | 55.653 | 60.787 | n/a | n/a |
| `sha512` | **38.812** | 40.368 | 42.457 | n/a | n/a |
| `x25519` | **27.620** | 41.991 | 43.270 | n/a | n/a |

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
| _(floor: empty program)_ | _4.139_ | _107.107_ | _**111.246**_ | _60.994_ | _78.426_ | _56.111_ |
| `lcg` | 4.302 | 115.752 | **120.054** | 59.426 | 84.732 | 62.054 |
| `packet_classifier` | 4.473 | 121.024 | **125.497** | 60.852 | 89.439 | 64.295 |
| `ring_write` | 13.468 | 119.263 | **132.731** | 67.011 | 88.907 | 65.239 |
| `histogram_bins` | 12.883 | 119.779 | **132.662** | 65.903 | 100.524 | 73.348 |
| `prefix_scan` | 13.440 | 120.584 | **134.024** | 68.772 | 93.415 | 69.495 |
| `binary_search` | 13.668 | 121.218 | **134.886** | 68.460 | 90.171 | 69.031 |
| `sort_window` | 13.787 | 120.604 | **134.391** | 67.792 | 97.432 | 72.060 |
| `bloom_filter` | 13.813 | 123.686 | **137.499** | 70.067 | 97.531 | 71.640 |
| `hash_join` | 17.164 | 222.191 | **239.355** | 72.634 | 180.318 | 110.334 |
| `sieve` | 13.966 | 122.318 | **136.284** | 69.068 | 98.902 | 74.686 |
| `fib` | 4.479 | 118.279 | **122.758** | 61.194 | 88.279 | 64.916 |
| `collatz` | 4.627 | 119.576 | **124.203** | 61.632 | 89.062 | 65.622 |
| `matmul` | 14.256 | 120.311 | **134.567** | 69.163 | 100.037 | 83.919 |
| `json_parse` | 40.891 | 370.613 | **411.504** | 98.824 | 142.042 | 150.633 |
| `nbody` | 15.674 | 126.442 | **142.116** | 72.499 | 114.746 | 95.338 |
| `chacha20` | 46.857 | 600.985 | **647.842** | 105.261 | 126.681 | 107.880 |
| `poly1305` | 35.593 | 415.075 | **450.668** | 92.888 | 127.688 | 117.033 |
| `blake2b` | 32.345 | 304.078 | **336.423** | 88.277 | 130.373 | 115.843 |
| `sha512` | 31.521 | 372.581 | **404.102** | 86.509 | 122.912 | 103.494 |
| `x25519` | 43.365 | 987.994 | **1031.359** | 99.234 | 941.598 | 408.320 |

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
