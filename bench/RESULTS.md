# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T19:53:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `7b9ddf56d83af1da6a40a9e01218717c2b381ea8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40943164166 |
| NURL | `v0.80.0-75-g7b9ddf56` |
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
| _(floor: empty program)_ | _1.521_ | _1.490_ | _1.703_ | _23.682_ | _17.518_ |
| `lcg` | 39.196 | **39.100** | 39.256 | 1820.299 | 5078.465 |
| `packet_classifier` | 56.291 | **56.177** | 56.456 | 163.122 | 4596.198 |
| `ring_write` | **42.200** | 42.253 | 42.601 | 68.611 | 6450.367 |
| `histogram_bins` | **39.571** | 40.709 | 40.900 | 67.118 | 6042.526 |
| `prefix_scan` | 21.837 | **21.828** | 21.983 | 67.744 | 4563.702 |
| `binary_search` | 39.819 | **38.331** | 41.122 | 108.415 | 6053.243 |
| `sort_window` | 26.620 | **26.608** | 26.871 | 199.061 | 14749.587 |
| `bloom_filter` | **16.725** | 17.942 | 18.454 | 2857.513 | 7380.590 |
| `hash_join` | **26.999** | 27.953 | 29.334 | 3484.061 | 8305.875 |
| `sieve` | 24.538 | **23.527** | 23.968 | 70.825 | 3238.070 |
| `fib` | **25.242** | 29.853 | 30.082 | 132.534 | 1355.793 |
| `collatz` | 12.328 | **12.203** | 12.457 | 51.046 | 745.972 |
| `matmul` | 33.842 | **33.478** | 33.794 | 77.025 | 3230.143 |
| `json_parse` | **8.550** | 8.637 | 11.944 | 37.082 | 39.540 |
| `nbody` | 25.352 | 39.868 | **25.348** | 102.349 | 3116.910 |
| `chacha20` | **7.364** | 40.594 | 33.848 | n/a | n/a |
| `poly1305` | **11.866** | 31.908 | 21.341 | n/a | n/a |
| `blake2b` | **44.247** | 65.068 | 69.276 | n/a | n/a |
| `sha512` | **47.554** | 50.624 | 49.554 | n/a | n/a |
| `x25519` | **31.625** | 48.638 | 49.481 | n/a | n/a |

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
| _(floor: empty program)_ | _4.688_ | _115.605_ | _**120.293**_ | _64.175_ | _83.771_ | _62.139_ |
| `lcg` | 4.847 | 129.468 | **134.315** | 64.007 | 93.655 | 70.511 |
| `packet_classifier` | 4.954 | 131.558 | **136.512** | 64.559 | 94.592 | 71.446 |
| `ring_write` | 15.515 | 133.014 | **148.529** | 73.790 | 97.157 | 73.926 |
| `histogram_bins` | 15.532 | 132.764 | **148.296** | 73.287 | 111.740 | 82.113 |
| `prefix_scan` | 15.741 | 135.883 | **151.624** | 74.151 | 101.924 | 76.467 |
| `binary_search` | 15.532 | 134.357 | **149.889** | 74.286 | 96.339 | 76.963 |
| `sort_window` | 16.006 | 136.625 | **152.631** | 74.552 | 107.808 | 83.189 |
| `bloom_filter` | 16.454 | 137.130 | **153.584** | 74.962 | 106.581 | 77.771 |
| `hash_join` | 19.958 | 268.162 | **288.120** | 78.599 | 221.453 | 124.453 |
| `sieve` | 15.911 | 132.344 | **148.255** | 74.007 | 105.607 | 84.156 |
| `fib` | 5.059 | 133.521 | **138.580** | 66.970 | 97.038 | 70.851 |
| `collatz` | 5.259 | 135.191 | **140.450** | 65.479 | 95.373 | 72.385 |
| `matmul` | 17.126 | 136.424 | **153.550** | 77.232 | 110.411 | 94.048 |
| `json_parse` | 51.370 | 479.569 | **530.939** | 112.767 | 166.435 | 174.713 |
| `nbody` | 18.687 | 142.970 | **161.657** | 78.720 | 133.022 | 109.019 |
| `chacha20` | 57.937 | 762.257 | **820.194** | 117.791 | 144.515 | 122.331 |
| `poly1305` | 44.816 | 518.043 | **562.859** | 105.148 | 146.018 | 135.457 |
| `blake2b` | 40.513 | 384.688 | **425.201** | 103.176 | 154.055 | 133.556 |
| `sha512` | 40.358 | 484.842 | **525.200** | 101.699 | 145.882 | 117.822 |
| `x25519` | 54.881 | 1301.030 | **1355.911** | 117.383 | 1237.990 | 512.374 |

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
