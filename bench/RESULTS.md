# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-08T15:40:18Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `7d302f691ce28eacfaf73e556a9d307caeca8922` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37801881103 |
| NURL | `v0.71.0-9-g7d302f69` |
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
| _(floor: empty program)_ | _1.435_ | _1.453_ | _1.647_ | _22.625_ | _17.535_ |
| `lcg` | **39.110** | 39.168 | 39.359 | 1896.849 | 5067.855 |
| `packet_classifier` | 56.360 | **56.329** | 56.523 | 161.508 | 4371.420 |
| `ring_write` | **42.213** | 42.354 | 42.502 | 66.937 | 6566.343 |
| `histogram_bins` | **39.529** | 40.669 | 40.939 | 65.666 | 6188.322 |
| `prefix_scan` | 21.713 | **21.679** | 21.985 | 65.719 | 4445.776 |
| `binary_search` | 39.477 | **38.143** | 41.110 | 108.671 | 6372.097 |
| `sort_window` | 26.569 | **26.472** | 26.694 | 197.362 | 11200.111 |
| `bloom_filter` | **15.311** | 17.770 | 18.388 | 2845.709 | 7750.536 |
| `hash_join` | **26.620** | 28.006 | 29.348 | 3422.265 | 8157.873 |
| `sieve` | 18.359 | 18.269 | **18.023** | 66.576 | 3218.582 |
| `fib` | **25.104** | 29.693 | 29.980 | 131.330 | 1371.018 |
| `collatz` | 12.300 | **12.214** | 12.466 | 52.172 | 743.032 |
| `matmul` | **33.424** | 33.448 | 33.678 | 75.981 | 3156.560 |
| `json_parse` | **8.488** | 8.588 | 11.822 | 35.330 | 38.826 |
| `nbody` | 25.284 | 39.887 | **25.260** | 100.188 | 3106.649 |
| `chacha20` | **21.162** | 42.102 | 33.713 | n/a | n/a |
| `poly1305` | 40.818 | **39.153** | 44.629 | n/a | n/a |
| `blake2b` | 184.347 | **65.014** | 69.341 | n/a | n/a |
| `sha512` | 49.927 | 50.604 | **49.481** | n/a | n/a |
| `x25519` | 56.710 | **48.552** | 49.470 | n/a | n/a |

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
| _(floor: empty program)_ | _3.363_ | _99.223_ | _**102.586**_ | _59.906_ | _79.131_ | _59.864_ |
| `lcg` | 3.677 | 110.656 | **114.333** | 60.721 | 89.372 | 66.883 |
| `packet_classifier` | 3.814 | 113.072 | **116.886** | 61.927 | 91.619 | 67.236 |
| `ring_write` | 3.954 | 113.399 | **117.353** | 60.822 | 92.920 | 70.239 |
| `histogram_bins` | 4.080 | 121.315 | **125.395** | 61.795 | 109.883 | 75.628 |
| `prefix_scan` | 4.155 | 114.109 | **118.264** | 60.849 | 97.719 | 72.548 |
| `binary_search` | 4.415 | 115.126 | **119.541** | 62.513 | 94.343 | 74.073 |
| `sort_window` | 4.489 | 114.526 | **119.015** | 60.963 | 100.944 | 77.377 |
| `bloom_filter` | 5.040 | 116.770 | **121.810** | 62.250 | 102.383 | 75.145 |
| `hash_join` | 8.953 | 264.214 | **273.167** | 65.303 | 218.192 | 119.793 |
| `sieve` | 4.393 | 111.262 | **115.655** | 60.667 | 101.291 | 78.357 |
| `fib` | 3.882 | 109.858 | **113.740** | 60.691 | 89.231 | 66.982 |
| `collatz` | 3.993 | 115.559 | **119.552** | 61.925 | 94.565 | 70.329 |
| `matmul` | 5.661 | 115.332 | **120.993** | 61.927 | 104.918 | 91.406 |
| `json_parse` | 46.751 | 480.356 | **527.107** | 105.558 | 160.001 | 165.315 |
| `nbody` | 6.836 | 131.781 | **138.617** | 62.743 | 126.293 | 104.776 |
| `chacha20` | 38.531 | 330.045 | **368.576** | 93.881 | 138.236 | 113.090 |
| `poly1305` | 22.885 | 228.364 | **251.249** | 79.028 | 150.130 | 136.812 |
| `blake2b` | 36.369 | 423.451 | **459.820** | 93.861 | 146.689 | 125.399 |
| `sha512` | 32.321 | 427.440 | **459.761** | 89.083 | 138.029 | 108.822 |
| `x25519` | 39.329 | 376.036 | **415.365** | 96.453 | 1220.691 | 520.688 |

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
