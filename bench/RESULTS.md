# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-01T00:59:25Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `36b5c909a4068981648c135719b54b151eb229d2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41258725091 |
| NURL | `v0.83.0` |
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
| _(floor: empty program)_ | _3.383_ | _3.303_ | _3.569_ | _26.255_ | _15.133_ |
| `lcg` | **41.116** | 41.223 | 41.339 | 1796.030 | 4816.886 |
| `packet_classifier` | **58.710** | 59.119 | 59.215 | 168.071 | 4005.781 |
| `ring_write` | 44.696 | **44.624** | 44.812 | 72.368 | 6273.769 |
| `histogram_bins` | **41.896** | 43.067 | 43.153 | 72.285 | 5709.428 |
| `prefix_scan` | 24.316 | **24.170** | 24.287 | 70.008 | 4129.492 |
| `binary_search` | 42.332 | **41.090** | 43.809 | 111.809 | 6822.281 |
| `sort_window` | 29.327 | **29.159** | 29.414 | 199.234 | 12256.408 |
| `bloom_filter` | **19.172** | 20.515 | 20.982 | 2869.449 | 7123.059 |
| `hash_join` | 29.506 | **29.173** | 31.822 | 3461.564 | 7732.983 |
| `sieve` | 24.797 | **24.431** | 24.518 | 73.204 | 3215.866 |
| `fib` | **27.478** | 31.976 | 32.161 | 136.518 | 1109.527 |
| `collatz` | 14.281 | **14.213** | 14.412 | 54.090 | 705.747 |
| `matmul` | 35.996 | **35.810** | 35.973 | 74.736 | 3003.997 |
| `json_parse` | **10.292** | 13.322 | 18.769 | 41.077 | 37.006 |
| `nbody` | **26.314** | 41.656 | 27.401 | 103.335 | 2986.283 |
| `chacha20` | **9.815** | 44.875 | 36.063 | n/a | n/a |
| `poly1305` | **13.573** | 33.901 | 23.267 | n/a | n/a |
| `blake2b` | **46.150** | 67.108 | 71.556 | n/a | n/a |
| `sha512` | **49.630** | 49.896 | 51.753 | n/a | n/a |
| `x25519` | **33.840** | 59.898 | 51.838 | n/a | n/a |

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
| _(floor: empty program)_ | _6.592_ | _120.342_ | _**126.934**_ | _64.579_ | _81.908_ | _64.369_ |
| `lcg` | 6.888 | 131.408 | **138.296** | 63.977 | 89.704 | 72.403 |
| `packet_classifier` | 6.834 | 131.462 | **138.296** | 64.911 | 92.584 | 73.300 |
| `ring_write` | 16.836 | 138.539 | **155.375** | 76.023 | 94.827 | 75.286 |
| `histogram_bins` | 16.906 | 139.574 | **156.480** | 78.477 | 137.115 | 83.595 |
| `prefix_scan` | 17.375 | 142.361 | **159.736** | 77.509 | 103.624 | 79.889 |
| `binary_search` | 17.317 | 137.298 | **154.615** | 75.420 | 100.042 | 83.180 |
| `sort_window` | 17.563 | 142.112 | **159.675** | 78.124 | 108.529 | 87.270 |
| `bloom_filter` | 18.418 | 147.655 | **166.073** | 80.365 | 108.106 | 84.935 |
| `hash_join` | 21.603 | 279.900 | **301.503** | 83.082 | 226.702 | 129.676 |
| `sieve` | 16.775 | 137.913 | **154.688** | 77.654 | 107.419 | 87.589 |
| `fib` | 7.012 | 132.961 | **139.973** | 65.325 | 93.102 | 73.906 |
| `collatz` | 7.069 | 134.791 | **141.860** | 65.344 | 93.204 | 73.071 |
| `matmul` | 17.492 | 139.261 | **156.753** | 77.434 | 109.666 | 97.762 |
| `json_parse` | 50.442 | 461.387 | **511.829** | 112.151 | 162.397 | 179.336 |
| `nbody` | 19.317 | 142.965 | **162.282** | 78.563 | 128.890 | 110.823 |
| `chacha20` | 69.884 | 691.211 | **761.095** | 129.289 | 145.683 | 123.654 |
| `poly1305` | 58.006 | 414.232 | **472.238** | 118.533 | 150.261 | 137.225 |
| `blake2b` | 39.259 | 341.050 | **380.309** | 99.572 | 148.020 | 132.697 |
| `sha512` | 39.875 | 459.704 | **499.579** | 100.202 | 143.436 | 120.164 |
| `x25519` | 54.504 | 1581.560 | **1636.064** | 115.296 | 1254.635 | 519.185 |

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
