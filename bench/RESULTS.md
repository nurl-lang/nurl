# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T23:31:00Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `10b54e384d541c6fc107c8be1791164c1f72749e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41144315650 |
| NURL | `v0.81.0-19-g10b54e38` |
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
| _(floor: empty program)_ | _3.615_ | _3.619_ | _3.941_ | _27.823_ | _16.011_ |
| `lcg` | 41.990 | **41.775** | 42.187 | 1799.112 | 4902.120 |
| `packet_classifier` | 58.983 | **58.957** | 59.124 | 167.747 | 4002.568 |
| `ring_write` | 44.859 | **44.706** | 44.953 | 71.445 | 6170.341 |
| `histogram_bins` | **42.106** | 43.314 | 43.426 | 72.039 | 5672.523 |
| `prefix_scan` | 24.164 | **24.144** | 24.176 | 69.926 | 4407.731 |
| `binary_search` | 42.220 | **40.889** | 43.632 | 110.647 | 6058.861 |
| `sort_window` | 29.221 | **29.117** | 29.235 | 200.589 | 11985.842 |
| `bloom_filter` | **19.217** | 20.613 | 20.718 | 2820.434 | 7418.826 |
| `hash_join` | 29.392 | **29.104** | 31.951 | 3402.440 | 7722.973 |
| `sieve` | 26.995 | **26.844** | 27.180 | 76.453 | 3181.058 |
| `fib` | **27.952** | 32.430 | 32.471 | 138.434 | 1135.569 |
| `collatz` | **14.579** | 14.714 | 14.721 | 57.997 | 699.076 |
| `matmul` | 36.575 | **36.198** | 36.468 | 75.435 | 2901.058 |
| `json_parse` | **10.598** | 13.784 | 19.114 | 40.943 | 38.212 |
| `nbody` | **26.471** | 42.261 | 27.735 | 105.396 | 2981.499 |
| `chacha20` | **9.382** | 44.783 | 36.127 | n/a | n/a |
| `poly1305` | **13.670** | 34.447 | 23.851 | n/a | n/a |
| `blake2b` | **46.603** | 67.427 | 71.940 | n/a | n/a |
| `sha512` | **50.115** | 50.179 | 52.292 | n/a | n/a |
| `x25519` | **33.953** | 51.832 | 51.956 | n/a | n/a |

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
| _(floor: empty program)_ | _7.123_ | _127.556_ | _**134.679**_ | _68.699_ | _85.834_ | _67.222_ |
| `lcg` | 6.925 | 130.670 | **137.595** | 67.500 | 97.631 | 73.898 |
| `packet_classifier` | 7.133 | 134.472 | **141.605** | 67.177 | 97.903 | 76.891 |
| `ring_write` | 17.780 | 134.185 | **151.965** | 78.398 | 99.910 | 78.676 |
| `histogram_bins` | 18.069 | 136.969 | **155.038** | 77.364 | 141.671 | 83.430 |
| `prefix_scan` | 17.828 | 134.576 | **152.404** | 77.988 | 103.633 | 80.271 |
| `binary_search` | 18.191 | 136.164 | **154.355** | 80.050 | 102.321 | 80.809 |
| `sort_window` | 17.994 | 135.627 | **153.621** | 77.996 | 109.538 | 87.970 |
| `bloom_filter` | 19.231 | 138.770 | **158.001** | 79.924 | 109.105 | 83.645 |
| `hash_join` | 22.253 | 274.026 | **296.279** | 82.741 | 226.093 | 132.167 |
| `sieve` | 18.317 | 133.788 | **152.105** | 78.841 | 109.787 | 91.203 |
| `fib` | 7.159 | 132.018 | **139.177** | 71.150 | 97.838 | 76.376 |
| `collatz` | 7.222 | 131.821 | **139.043** | 66.450 | 97.983 | 77.390 |
| `matmul` | 19.870 | 135.379 | **155.249** | 79.810 | 115.714 | 98.700 |
| `json_parse` | 53.223 | 465.640 | **518.863** | 115.546 | 165.156 | 180.306 |
| `nbody` | 20.926 | 143.555 | **164.481** | 81.923 | 134.728 | 115.357 |
| `chacha20` | 61.391 | 792.589 | **853.980** | 122.582 | 150.304 | 126.240 |
| `poly1305` | 47.098 | 517.203 | **564.301** | 108.674 | 153.837 | 144.553 |
| `blake2b` | 43.044 | 346.139 | **389.183** | 105.398 | 152.519 | 142.744 |
| `sha512` | 41.616 | 464.332 | **505.948** | 102.039 | 146.375 | 122.982 |
| `x25519` | 57.252 | 1562.887 | **1620.139** | 118.508 | 1264.027 | 518.393 |

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
