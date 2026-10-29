# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T20:30:31Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `9e261100577ced5e9ff5ce1b1675a088fb8e2c05` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40948698686 |
| NURL | `v0.80.0-77-g9e261100` |
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
| _(floor: empty program)_ | _1.650_ | _1.653_ | _1.943_ | _27.094_ | _19.038_ |
| `lcg` | 44.341 | **44.215** | 44.523 | 1833.445 | 5428.401 |
| `packet_classifier` | 63.709 | **63.614** | 63.852 | 159.994 | 4764.412 |
| `ring_write` | **47.723** | 47.785 | 48.011 | 76.249 | 6500.639 |
| `histogram_bins` | 44.843 | **44.787** | 45.058 | 77.810 | 6510.154 |
| `prefix_scan` | **24.619** | 24.643 | 24.948 | 76.516 | 4939.433 |
| `binary_search` | 41.801 | **35.903** | 43.457 | 114.841 | 6078.987 |
| `sort_window` | 30.326 | **30.185** | 30.487 | 167.457 | 12028.724 |
| `bloom_filter` | **17.393** | 18.779 | 20.787 | 2740.662 | 7867.064 |
| `hash_join` | **27.972** | 28.709 | 30.357 | 3403.357 | 8418.193 |
| `sieve` | 25.859 | **24.389** | 24.491 | 76.295 | 3439.584 |
| `fib` | **28.032** | 33.198 | 33.470 | 143.813 | 1288.575 |
| `collatz` | 13.811 | **13.678** | 14.026 | 54.453 | 751.648 |
| `matmul` | **44.892** | 45.387 | 45.532 | 85.420 | 3432.629 |
| `json_parse` | **8.088** | 9.016 | 12.273 | 40.793 | 40.105 |
| `nbody` | **26.787** | 45.066 | 26.933 | 97.002 | 3257.640 |
| `chacha20` | **8.681** | 46.124 | 35.677 | n/a | n/a |
| `poly1305` | **12.563** | 40.311 | 23.996 | n/a | n/a |
| `blake2b` | **49.383** | 71.683 | 78.317 | n/a | n/a |
| `sha512` | **49.915** | 52.000 | 54.850 | n/a | n/a |
| `x25519` | **35.594** | 54.191 | 55.976 | n/a | n/a |

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
| _(floor: empty program)_ | _5.142_ | _130.791_ | _**135.933**_ | _72.665_ | _97.980_ | _72.307_ |
| `lcg` | 5.452 | 147.520 | **152.972** | 74.895 | 105.952 | 77.603 |
| `packet_classifier` | 5.507 | 146.411 | **151.918** | 74.220 | 109.668 | 109.850 |
| `ring_write` | 16.717 | 147.565 | **164.282** | 84.366 | 110.795 | 80.446 |
| `histogram_bins` | 16.921 | 146.570 | **163.491** | 83.486 | 124.677 | 89.632 |
| `prefix_scan` | 17.065 | 148.802 | **165.867** | 83.855 | 114.337 | 85.374 |
| `binary_search` | 17.256 | 150.298 | **167.554** | 85.921 | 113.224 | 90.326 |
| `sort_window` | 17.098 | 151.439 | **168.537** | 85.726 | 121.232 | 91.702 |
| `bloom_filter` | 17.634 | 150.352 | **167.986** | 85.756 | 117.363 | 85.261 |
| `hash_join` | 20.875 | 267.352 | **288.227** | 85.957 | 221.692 | 131.014 |
| `sieve` | 16.922 | 145.724 | **162.646** | 83.580 | 118.511 | 91.960 |
| `fib` | 5.556 | 144.236 | **149.792** | 74.589 | 104.880 | 78.355 |
| `collatz` | 5.731 | 149.624 | **155.355** | 74.909 | 107.498 | 79.739 |
| `matmul` | 18.213 | 147.026 | **165.239** | 85.229 | 120.788 | 100.974 |
| `json_parse` | 51.920 | 464.572 | **516.492** | 119.719 | 171.431 | 184.253 |
| `nbody` | 19.251 | 151.553 | **170.804** | 86.457 | 142.616 | 117.342 |
| `chacha20` | 58.656 | 749.135 | **807.791** | 126.759 | 153.481 | 130.591 |
| `poly1305` | 44.614 | 511.872 | **556.486** | 111.990 | 154.842 | 142.235 |
| `blake2b` | 40.440 | 378.750 | **419.190** | 107.730 | 158.311 | 139.495 |
| `sha512` | 40.886 | 472.634 | **513.520** | 109.175 | 155.189 | 127.814 |
| `x25519` | 55.495 | 1262.416 | **1317.911** | 124.953 | 1208.462 | 521.495 |

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
