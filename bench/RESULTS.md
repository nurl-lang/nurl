# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T08:09:09Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `56573129a8a6a64db5aa57694dc5a78372a7e5e1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41182907591 |
| NURL | `v0.82.0-6-g56573129` |
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
| _(floor: empty program)_ | _3.505_ | _3.366_ | _3.606_ | _27.895_ | _15.017_ |
| `lcg` | 41.382 | **41.272** | 41.442 | 1785.532 | 4917.385 |
| `packet_classifier` | 58.603 | **58.552** | 58.889 | 167.579 | 4073.220 |
| `ring_write` | **44.586** | 44.625 | 44.798 | 72.228 | 6117.248 |
| `histogram_bins` | **41.807** | 42.832 | 42.907 | 74.084 | 5655.502 |
| `prefix_scan` | 23.951 | **23.945** | 24.037 | 68.515 | 4094.745 |
| `binary_search` | 42.070 | **40.318** | 43.309 | 111.659 | 7250.206 |
| `sort_window` | 29.168 | **29.041** | 29.223 | 200.171 | 14106.513 |
| `bloom_filter` | **19.188** | 20.386 | 20.841 | 2915.621 | 7219.110 |
| `hash_join` | 29.988 | **29.441** | 32.149 | 3509.244 | 7725.912 |
| `sieve` | 26.471 | **25.825** | 27.064 | 75.471 | 3402.785 |
| `fib` | **27.821** | 32.329 | 32.370 | 137.607 | 1104.057 |
| `collatz` | 14.576 | **14.387** | 14.645 | 54.871 | 703.313 |
| `matmul` | 35.698 | **35.557** | 35.836 | 76.126 | 2913.825 |
| `json_parse` | **10.620** | 13.706 | 19.096 | 40.240 | 38.518 |
| `nbody` | **26.481** | 41.891 | 27.358 | 104.386 | 3019.363 |
| `chacha20` | **9.409** | 44.529 | 36.021 | n/a | n/a |
| `poly1305` | **13.639** | 33.842 | 23.149 | n/a | n/a |
| `blake2b` | **45.974** | 66.709 | 71.301 | n/a | n/a |
| `sha512` | **49.434** | 49.586 | 51.719 | n/a | n/a |
| `x25519` | **33.889** | 51.430 | 51.662 | n/a | n/a |

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
| _(floor: empty program)_ | _6.888_ | _123.184_ | _**130.072**_ | _64.703_ | _80.434_ | _64.970_ |
| `lcg` | 6.876 | 129.449 | **136.325** | 63.864 | 89.956 | 71.125 |
| `packet_classifier` | 7.226 | 132.482 | **139.708** | 65.984 | 93.198 | 75.090 |
| `ring_write` | 17.140 | 132.274 | **149.414** | 74.687 | 94.907 | 75.488 |
| `histogram_bins` | 16.987 | 131.638 | **148.625** | 73.310 | 135.349 | 80.864 |
| `prefix_scan` | 17.103 | 132.508 | **149.611** | 73.240 | 97.593 | 77.735 |
| `binary_search` | 17.308 | 134.373 | **151.681** | 76.091 | 96.437 | 80.232 |
| `sort_window` | 17.679 | 137.313 | **154.992** | 76.117 | 106.020 | 85.673 |
| `bloom_filter` | 18.041 | 139.413 | **157.454** | 77.666 | 105.619 | 83.337 |
| `hash_join` | 21.547 | 277.523 | **299.070** | 82.232 | 229.695 | 130.797 |
| `sieve` | 17.834 | 138.785 | **156.619** | 78.353 | 109.366 | 90.158 |
| `fib` | 7.364 | 134.774 | **142.138** | 67.264 | 94.627 | 76.870 |
| `collatz` | 7.262 | 132.542 | **139.804** | 65.428 | 94.009 | 76.260 |
| `matmul` | 17.688 | 133.771 | **151.459** | 75.094 | 108.338 | 96.648 |
| `json_parse` | 50.409 | 452.424 | **502.833** | 108.755 | 160.266 | 178.663 |
| `nbody` | 19.345 | 141.678 | **161.023** | 77.685 | 128.750 | 111.491 |
| `chacha20` | 57.131 | 781.546 | **838.677** | 116.156 | 145.940 | 124.310 |
| `poly1305` | 44.756 | 510.787 | **555.543** | 103.330 | 147.890 | 137.887 |
| `blake2b` | 39.514 | 336.006 | **375.520** | 97.790 | 145.279 | 133.473 |
| `sha512` | 39.527 | 453.565 | **493.092** | 97.869 | 140.834 | 118.731 |
| `x25519` | 54.725 | 1541.439 | **1596.164** | 112.513 | 1244.303 | 513.626 |

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
