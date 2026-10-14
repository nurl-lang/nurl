# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-14T04:06:58Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `398d14c7725e1cc77fb656464f293ca5b17693c9` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38509304304 |
| NURL | `v0.72.0-15-g398d14c7` |
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
| _(floor: empty program)_ | _1.224_ | _1.199_ | _1.383_ | _18.904_ | _13.708_ |
| `lcg` | **34.145** | 34.187 | 34.294 | 1411.600 | 4019.970 |
| `packet_classifier` | **49.197** | 49.228 | 49.354 | 123.951 | 3661.106 |
| `ring_write` | 36.940 | **36.864** | 37.061 | 56.673 | 5404.754 |
| `histogram_bins` | 34.589 | **34.498** | 34.746 | 58.912 | 5095.824 |
| `prefix_scan` | 18.948 | **18.889** | 19.094 | 55.871 | 3718.645 |
| `binary_search` | 31.960 | **27.658** | 33.445 | 87.343 | 5288.226 |
| `sort_window` | **23.209** | 23.236 | 23.437 | 129.306 | 8717.413 |
| `bloom_filter` | **13.435** | 14.521 | 16.024 | 2129.498 | 5998.296 |
| `hash_join` | **21.556** | 22.197 | 23.447 | 2669.894 | 6312.234 |
| `sieve` | 15.961 | **15.594** | 15.755 | 55.627 | 2593.452 |
| `fib` | **21.563** | 25.674 | 25.822 | 110.946 | 998.446 |
| `collatz` | 10.660 | **10.591** | 10.765 | 41.248 | 581.906 |
| `matmul` | **34.966** | 35.549 | 35.706 | 64.854 | 2605.096 |
| `json_parse` | **6.238** | 6.887 | 9.387 | 30.360 | 30.235 |
| `nbody` | **20.719** | 34.822 | 20.825 | 73.683 | 2496.561 |
| `chacha20` | **7.012** | 35.665 | 27.531 | n/a | n/a |
| `poly1305` | 20.370 | 31.197 | **18.492** | n/a | n/a |
| `blake2b` | **37.750** | 55.436 | 61.315 | n/a | n/a |
| `sha512` | **38.637** | 40.071 | 42.192 | n/a | n/a |
| `x25519` | **37.999** | 41.978 | 43.373 | n/a | n/a |

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
| _(floor: empty program)_ | _3.628_ | _86.385_ | _**90.013**_ | _53.553_ | _71.116_ | _52.582_ |
| `lcg` | 3.680 | 97.727 | **101.407** | 54.263 | 78.250 | 61.183 |
| `packet_classifier` | 3.783 | 94.993 | **98.776** | 53.314 | 80.273 | 59.209 |
| `ring_write` | 10.462 | 99.025 | **109.487** | 60.260 | 79.443 | 59.787 |
| `histogram_bins` | 10.595 | 103.128 | **113.723** | 60.411 | 91.834 | 65.887 |
| `prefix_scan` | 10.407 | 98.557 | **108.964** | 60.210 | 84.062 | 62.935 |
| `binary_search` | 10.697 | 100.081 | **110.778** | 60.699 | 81.279 | 63.845 |
| `sort_window` | 10.715 | 100.687 | **111.402** | 60.423 | 88.044 | 69.085 |
| `bloom_filter` | 11.065 | 101.875 | **112.940** | 61.366 | 87.013 | 65.729 |
| `hash_join` | 13.769 | 206.322 | **220.091** | 64.023 | 168.770 | 100.815 |
| `sieve` | 10.683 | 98.224 | **108.907** | 60.411 | 87.143 | 69.864 |
| `fib` | 3.859 | 97.344 | **101.203** | 53.613 | 78.215 | 59.261 |
| `collatz` | 3.927 | 98.297 | **102.224** | 53.733 | 80.301 | 60.033 |
| `matmul` | 11.551 | 98.696 | **110.247** | 61.894 | 89.144 | 75.246 |
| `json_parse` | 32.474 | 366.771 | **399.245** | 83.990 | 130.623 | 138.663 |
| `nbody` | 12.285 | 113.328 | **125.613** | 62.117 | 105.226 | 89.231 |
| `chacha20` | 34.146 | 463.006 | **497.152** | 85.712 | 115.856 | 98.303 |
| `poly1305` | 22.951 | 211.337 | **234.288** | 73.566 | 117.110 | 109.325 |
| `blake2b` | 24.855 | 279.338 | **304.193** | 76.192 | 119.957 | 105.188 |
| `sha512` | 25.070 | 358.490 | **383.560** | 75.858 | 113.920 | 94.676 |
| `x25519` | 29.561 | 543.335 | **572.896** | 80.604 | 929.760 | 398.713 |

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
