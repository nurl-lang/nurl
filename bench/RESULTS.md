# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-08T09:02:22Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366632 KiB |
| Commit | `0f4b5dc89777064aeb493a3168c85330272cbfe7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42465091694 |
| NURL | `v0.90.0-3-g0f4b5dc8` |
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
| _(floor: empty program)_ | _2.937_ | _2.867_ | _3.047_ | _22.014_ | _12.597_ |
| `lcg` | 36.188 | **35.930** | 36.029 | 1454.407 | 4015.836 |
| `packet_classifier` | 51.203 | **51.088** | 51.625 | 127.403 | 3315.385 |
| `ring_write` | 38.765 | **38.694** | 38.912 | 61.215 | 4917.639 |
| `histogram_bins` | **36.376** | 36.399 | 36.541 | 62.410 | 4411.300 |
| `prefix_scan` | 20.707 | **20.688** | 20.861 | 57.316 | 3478.070 |
| `binary_search` | 33.839 | **29.490** | 35.417 | 89.414 | 4953.291 |
| `sort_window` | 25.063 | **25.000** | 25.180 | 127.965 | 8696.257 |
| `bloom_filter` | **15.456** | 16.420 | 17.901 | 2108.358 | 5804.424 |
| `hash_join` | 22.748 | **22.596** | 25.481 | 2602.364 | 5718.318 |
| `sieve` | 20.951 | **20.678** | 20.762 | 63.026 | 2430.909 |
| `fib` | **23.636** | 28.021 | 28.090 | 119.182 | 887.484 |
| `collatz` | 12.396 | **12.299** | 12.525 | 45.275 | 550.040 |
| `matmul` | 37.601 | **37.357** | 37.654 | 62.970 | 2402.711 |
| `json_parse` | **6.857** | 11.335 | 15.791 | 36.296 | 29.091 |
| `nbody` | **22.308** | 37.183 | 23.199 | 78.701 | 2495.178 |
| `chacha20` | **6.769** | 39.093 | 29.800 | n/a | n/a |
| `poly1305` | **12.785** | 33.213 | 20.612 | n/a | n/a |
| `blake2b` | **40.254** | 57.038 | 62.730 | n/a | n/a |
| `sha512` | 40.845 | **40.593** | 44.630 | n/a | n/a |
| `x25519` | **31.125** | 44.779 | 45.738 | n/a | n/a |

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
| _(floor: empty program)_ | _6.104_ | _102.002_ | _**108.106**_ | _55.924_ | _70.277_ | _57.211_ |
| `lcg` | 6.268 | 112.516 | **118.784** | 57.510 | 79.550 | 62.404 |
| `packet_classifier` | 6.502 | 112.479 | **118.981** | 58.167 | 80.785 | 63.910 |
| `ring_write` | 13.012 | 115.987 | **128.999** | 64.640 | 81.282 | 65.084 |
| `histogram_bins` | 13.177 | 115.988 | **129.165** | 64.655 | 113.025 | 70.655 |
| `prefix_scan` | 13.283 | 115.410 | **128.693** | 64.569 | 85.118 | 67.189 |
| `binary_search` | 13.366 | 114.463 | **127.829** | 63.933 | 81.730 | 67.998 |
| `sort_window` | 13.599 | 115.715 | **129.314** | 64.208 | 89.741 | 72.500 |
| `bloom_filter` | 13.990 | 116.941 | **130.931** | 65.244 | 87.407 | 69.192 |
| `hash_join` | 16.554 | 211.007 | **227.561** | 68.880 | 169.614 | 106.844 |
| `sieve` | 13.369 | 116.209 | **129.578** | 65.131 | 90.896 | 75.260 |
| `fib` | 6.613 | 114.490 | **121.103** | 58.554 | 81.848 | 65.100 |
| `collatz` | 6.478 | 115.975 | **122.453** | 58.686 | 82.540 | 65.500 |
| `matmul` | 14.015 | 118.633 | **132.648** | 66.289 | 94.671 | 83.328 |
| `json_parse` | 38.307 | 269.618 | **307.925** | 93.392 | 132.901 | 152.441 |
| `nbody` | 15.060 | 123.595 | **138.655** | 68.398 | 110.055 | 96.320 |
| `chacha20` | 51.796 | 539.169 | **590.965** | 105.052 | 123.521 | 108.183 |
| `poly1305` | 44.279 | 329.351 | **373.630** | 98.337 | 125.710 | 116.674 |
| `blake2b` | 29.934 | 270.425 | **300.359** | 82.589 | 123.830 | 113.728 |
| `sha512` | 29.685 | 353.604 | **383.289** | 84.135 | 122.011 | 103.408 |
| `x25519` | 41.839 | 1067.336 | **1109.175** | 96.864 | 951.440 | 418.935 |

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
