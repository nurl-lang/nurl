# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-19T21:15:38Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16367520 KiB |
| Commit | `8f2aab96de9760ce9243c703d9f7ef06f62af9c0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39325449196 |
| NURL | `v0.74.0` |
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
| _(floor: empty program)_ | _1.240_ | _1.214_ | _1.363_ | _18.332_ | _12.009_ |
| `lcg` | 28.389 | **28.076** | 29.193 | 1084.842 | 2903.893 |
| `packet_classifier` | 40.634 | 41.233 | **40.491** | 128.103 | 2617.877 |
| `ring_write` | 29.124 | **28.643** | 28.981 | 51.770 | 3512.845 |
| `histogram_bins` | 30.071 | 28.873 | **28.723** | 54.973 | 3611.123 |
| `prefix_scan` | 16.410 | **16.215** | 16.421 | 50.515 | 2564.550 |
| `binary_search` | **15.325** | 15.450 | 16.488 | 74.651 | 3706.719 |
| `sort_window` | 20.582 | **20.390** | 20.745 | 138.223 | 6582.527 |
| `bloom_filter` | 9.105 | **9.059** | 9.332 | 1659.691 | 4393.993 |
| `hash_join` | **16.681** | 17.095 | 18.218 | 1983.887 | 4650.312 |
| `sieve` | 16.096 | **15.374** | 15.730 | 51.469 | 1843.193 |
| `fib` | 20.042 | 19.861 | **19.628** | 80.765 | 687.880 |
| `collatz` | **9.514** | 9.547 | 9.717 | 38.925 | 422.612 |
| `matmul` | **20.326** | 20.592 | 20.679 | 56.279 | 1888.027 |
| `json_parse` | **5.116** | 5.650 | 7.179 | 27.756 | 25.631 |
| `nbody` | **17.178** | 25.357 | 17.807 | 63.705 | 1543.661 |
| `chacha20` | **6.997** | 20.211 | 19.962 | n/a | n/a |
| `poly1305` | **15.701** | 27.893 | 16.268 | n/a | n/a |
| `blake2b` | **27.021** | 44.517 | 49.624 | n/a | n/a |
| `sha512` | **30.721** | 34.002 | 33.495 | n/a | n/a |
| `x25519` | **29.103** | 31.500 | 32.398 | n/a | n/a |

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
| _(floor: empty program)_ | _3.484_ | _86.188_ | _**89.672**_ | _52.453_ | _70.079_ | _53.356_ |
| `lcg` | 3.460 | 90.583 | **94.043** | 49.662 | 76.699 | 59.539 |
| `packet_classifier` | 3.733 | 96.766 | **100.499** | 52.995 | 80.024 | 61.127 |
| `ring_write` | 9.212 | 95.352 | **104.564** | 57.995 | 78.093 | 59.365 |
| `histogram_bins` | 8.986 | 99.367 | **108.353** | 57.878 | 92.872 | 70.198 |
| `prefix_scan` | 9.698 | 101.833 | **111.531** | 61.811 | 86.667 | 67.821 |
| `binary_search` | 10.123 | 101.750 | **111.873** | 61.897 | 82.567 | 67.839 |
| `sort_window` | 9.684 | 99.909 | **109.593** | 59.256 | 88.982 | 67.248 |
| `bloom_filter` | 9.764 | 97.566 | **107.330** | 58.397 | 83.028 | 66.696 |
| `hash_join` | 12.313 | 185.488 | **197.801** | 61.750 | 149.804 | 97.074 |
| `sieve` | 9.857 | 100.043 | **109.900** | 62.448 | 114.843 | 71.318 |
| `fib` | 3.827 | 95.971 | **99.798** | 52.983 | 78.586 | 65.523 |
| `collatz` | 3.958 | 97.428 | **101.386** | 54.534 | 81.062 | 63.564 |
| `matmul` | 10.099 | 96.040 | **106.139** | 58.301 | 88.750 | 79.087 |
| `json_parse` | 30.046 | 338.166 | **368.212** | 82.390 | 126.957 | 141.370 |
| `nbody` | 11.000 | 111.821 | **122.821** | 62.171 | 104.116 | 90.161 |
| `chacha20` | 29.833 | 508.245 | **538.078** | 80.169 | 113.981 | 98.735 |
| `poly1305` | 20.997 | 197.961 | **218.958** | 71.661 | 112.331 | 113.454 |
| `blake2b` | 23.267 | 264.251 | **287.518** | 75.070 | 117.024 | 106.240 |
| `sha512` | 24.531 | 334.666 | **359.197** | 78.176 | 117.178 | 100.340 |
| `x25519` | 26.159 | 496.273 | **522.432** | 77.119 | 769.864 | 353.841 |

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
