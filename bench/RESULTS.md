# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-10T05:23:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `36f1c7c480a2cac5ff0f33436ec4a603d43f51fa` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38027060339 |
| NURL | `v0.71.0-20-g36f1c7c4` |
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
| _(floor: empty program)_ | _1.225_ | _1.262_ | _1.364_ | _23.422_ | _16.063_ |
| `lcg` | 40.306 | 40.114 | **39.655** | 1575.841 | 4004.384 |
| `packet_classifier` | **67.477** | 68.278 | 69.147 | 167.422 | 3424.247 |
| `ring_write` | 44.423 | **44.071** | 44.618 | 68.739 | 4935.915 |
| `histogram_bins` | 41.468 | 41.290 | **41.081** | 68.329 | 4703.703 |
| `prefix_scan` | **21.855** | 22.245 | 22.516 | 65.740 | 3720.712 |
| `binary_search` | 38.881 | **31.265** | 41.159 | 112.482 | 5693.864 |
| `sort_window` | 39.448 | **39.347** | 40.432 | 179.131 | 9235.075 |
| `bloom_filter` | 14.210 | **13.991** | 14.494 | 2378.351 | 6409.952 |
| `hash_join` | **23.266** | 24.857 | 24.872 | 2975.895 | 7030.499 |
| `sieve` | 36.268 | **35.970** | 36.129 | 85.636 | 2551.943 |
| `fib` | **29.068** | 30.001 | 29.092 | 112.293 | 886.106 |
| `collatz` | **14.748** | 15.019 | 15.761 | 58.848 | 564.876 |
| `matmul` | 20.016 | **19.715** | 20.368 | 71.922 | 2597.666 |
| `json_parse` | **6.752** | 7.231 | 9.425 | 32.307 | 32.857 |
| `nbody` | 21.994 | 30.959 | **21.986** | 79.666 | 2083.378 |
| `chacha20` | **8.273** | 36.351 | 30.988 | n/a | n/a |
| `poly1305` | 23.753 | 33.760 | **22.749** | n/a | n/a |
| `blake2b` | **42.377** | 48.431 | 52.975 | n/a | n/a |
| `sha512` | **42.008** | 42.937 | 46.476 | n/a | n/a |
| `x25519` | 41.898 | 41.763 | **40.967** | n/a | n/a |

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
| _(floor: empty program)_ | _3.506_ | _83.699_ | _**87.205**_ | _51.663_ | _64.062_ | _57.100_ |
| `lcg` | 3.626 | 95.996 | **99.622** | 51.660 | 72.486 | 64.252 |
| `packet_classifier` | 3.708 | 95.596 | **99.304** | 51.868 | 73.614 | 63.091 |
| `ring_write` | 3.951 | 97.497 | **101.448** | 53.765 | 75.518 | 64.425 |
| `histogram_bins` | 3.991 | 102.754 | **106.745** | 52.589 | 90.294 | 70.976 |
| `prefix_scan` | 4.217 | 97.931 | **102.148** | 53.375 | 81.059 | 65.438 |
| `binary_search` | 4.390 | 98.163 | **102.553** | 52.486 | 75.744 | 69.664 |
| `sort_window` | 4.440 | 101.130 | **105.570** | 53.859 | 85.880 | 75.174 |
| `bloom_filter` | 5.006 | 103.162 | **108.168** | 55.634 | 82.254 | 70.601 |
| `hash_join` | 8.844 | 223.683 | **232.527** | 57.718 | 178.725 | 113.909 |
| `sieve` | 4.218 | 95.770 | **99.988** | 52.302 | 83.670 | 74.975 |
| `fib` | 3.732 | 98.160 | **101.892** | 52.613 | 73.254 | 62.834 |
| `collatz` | 4.009 | 98.254 | **102.263** | 52.450 | 75.198 | 61.717 |
| `matmul` | 6.065 | 98.511 | **104.576** | 54.724 | 86.427 | 83.100 |
| `json_parse` | 47.663 | 412.914 | **460.577** | 97.417 | 132.158 | 165.400 |
| `nbody` | 6.535 | 113.009 | **119.544** | 54.989 | 106.570 | 99.262 |
| `chacha20` | 48.441 | 537.748 | **586.189** | 99.349 | 117.525 | 116.206 |
| `poly1305` | 32.168 | 225.312 | **257.480** | 81.779 | 121.600 | 126.005 |
| `blake2b` | 34.156 | 320.505 | **354.661** | 83.129 | 124.021 | 121.525 |
| `sha512` | 34.120 | 409.886 | **444.006** | 83.442 | 114.215 | 107.753 |
| `x25519` | 41.668 | 661.307 | **702.975** | 92.493 | 1151.846 | 490.279 |

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
