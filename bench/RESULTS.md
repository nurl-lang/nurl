# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-03T22:16:55Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `9ab0e5d2f39671e9249ee074021501b17f1056d8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41728490042 |
| NURL | `v0.86.0` |
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
| _(floor: empty program)_ | _3.834_ | _3.901_ | _4.062_ | _29.485_ | _15.925_ |
| `lcg` | 41.356 | **41.305** | 41.838 | 1788.980 | 5036.448 |
| `packet_classifier` | 58.801 | **58.668** | 58.936 | 168.086 | 4034.126 |
| `ring_write` | **44.860** | 44.928 | 45.288 | 72.787 | 6171.368 |
| `histogram_bins` | **41.920** | 42.897 | 43.226 | 70.392 | 5505.700 |
| `prefix_scan` | **23.911** | 24.036 | 24.298 | 69.101 | 4103.185 |
| `binary_search` | 41.992 | **40.299** | 43.127 | 110.489 | 6430.855 |
| `sort_window` | 28.814 | **28.769** | 29.166 | 199.542 | 12439.677 |
| `bloom_filter` | **18.785** | 19.949 | 20.447 | 2831.747 | 7212.189 |
| `hash_join` | 29.098 | **28.805** | 31.560 | 3351.010 | 7676.222 |
| `sieve` | 24.497 | **23.920** | 24.120 | 73.797 | 3133.762 |
| `fib` | **27.602** | 32.228 | 32.390 | 138.048 | 1118.496 |
| `collatz` | **14.475** | 14.718 | 14.728 | 54.731 | 708.044 |
| `matmul` | **35.692** | 35.743 | 36.038 | 74.738 | 2901.135 |
| `json_parse` | **8.676** | 14.011 | 18.879 | 40.904 | 37.306 |
| `nbody` | **26.460** | 42.168 | 27.575 | 107.084 | 2950.069 |
| `chacha20` | **9.943** | 43.402 | 35.903 | n/a | n/a |
| `poly1305` | **13.754** | 34.348 | 23.409 | n/a | n/a |
| `blake2b` | **46.345** | 67.350 | 71.740 | n/a | n/a |
| `sha512` | 49.908 | **49.602** | 51.948 | n/a | n/a |
| `x25519` | **34.810** | 51.470 | 51.755 | n/a | n/a |

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
| _(floor: empty program)_ | _7.379_ | _137.358_ | _**144.737**_ | _69.376_ | _84.832_ | _66.751_ |
| `lcg` | 7.788 | 140.156 | **147.944** | 69.373 | 96.869 | 74.820 |
| `packet_classifier` | 7.372 | 137.774 | **145.146** | 66.664 | 97.766 | 75.255 |
| `ring_write` | 16.106 | 138.164 | **154.270** | 74.957 | 97.289 | 75.528 |
| `histogram_bins` | 16.263 | 140.979 | **157.242** | 76.943 | 140.121 | 83.762 |
| `prefix_scan` | 16.207 | 140.087 | **156.294** | 76.050 | 102.420 | 79.199 |
| `binary_search` | 16.387 | 140.830 | **157.217** | 76.460 | 98.842 | 80.327 |
| `sort_window` | 16.829 | 143.588 | **160.417** | 76.255 | 109.196 | 90.307 |
| `bloom_filter` | 17.418 | 143.442 | **160.860** | 77.879 | 109.305 | 82.095 |
| `hash_join` | 20.628 | 274.800 | **295.428** | 80.105 | 221.729 | 128.496 |
| `sieve` | 16.037 | 137.092 | **153.129** | 75.049 | 106.793 | 88.408 |
| `fib` | 7.418 | 135.045 | **142.463** | 66.046 | 95.576 | 74.340 |
| `collatz` | 7.670 | 138.572 | **146.242** | 66.901 | 98.049 | 76.653 |
| `matmul` | 16.764 | 140.322 | **157.086** | 76.748 | 109.873 | 96.066 |
| `json_parse` | 47.418 | 344.428 | **391.846** | 107.378 | 164.698 | 184.416 |
| `nbody` | 18.909 | 146.142 | **165.051** | 78.477 | 133.012 | 114.789 |
| `chacha20` | 68.294 | 699.772 | **768.066** | 127.271 | 145.365 | 124.973 |
| `poly1305` | 56.919 | 423.221 | **480.140** | 117.602 | 151.673 | 139.521 |
| `blake2b` | 38.075 | 345.992 | **384.067** | 97.825 | 149.704 | 134.179 |
| `sha512` | 36.159 | 465.189 | **501.348** | 98.992 | 144.988 | 120.695 |
| `x25519` | 53.001 | 1407.495 | **1460.496** | 113.444 | 1267.763 | 523.089 |

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
