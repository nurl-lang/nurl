# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-10T15:33:47Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373444 KiB |
| Commit | `3483311b866fed85b827965075f43e8ced8419be` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38063729556 |
| NURL | `v0.72.0` |
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
| _(floor: empty program)_ | _1.429_ | _1.421_ | _1.603_ | _22.396_ | _16.744_ |
| `lcg` | **38.902** | 38.921 | 39.085 | 1917.043 | 5065.950 |
| `packet_classifier` | **56.123** | 56.139 | 56.234 | 160.789 | 4692.325 |
| `ring_write` | **42.013** | 42.035 | 42.246 | 65.761 | 6429.106 |
| `histogram_bins` | **39.468** | 40.507 | 40.730 | 65.055 | 6052.780 |
| `prefix_scan` | 21.608 | **21.568** | 21.766 | 63.222 | 4625.926 |
| `binary_search` | 39.496 | **38.207** | 40.611 | 106.251 | 5979.494 |
| `sort_window` | **26.460** | 26.489 | 26.661 | 196.066 | 11278.309 |
| `bloom_filter` | **15.292** | 17.810 | 18.316 | 2821.300 | 7659.905 |
| `hash_join` | **26.467** | 27.871 | 29.053 | 3393.443 | 8332.121 |
| `sieve` | 18.118 | 18.010 | **17.704** | 64.684 | 3385.141 |
| `fib` | **24.930** | 29.614 | 29.745 | 132.635 | 1367.170 |
| `collatz` | 12.208 | **12.179** | 12.440 | 47.757 | 739.949 |
| `matmul` | 36.570 | **33.367** | 33.441 | 75.743 | 3243.469 |
| `json_parse` | **8.246** | 8.551 | 11.743 | 34.815 | 38.761 |
| `nbody` | 25.134 | 39.558 | **25.091** | 98.270 | 3126.689 |
| `chacha20` | **7.619** | 40.175 | 33.437 | n/a | n/a |
| `poly1305` | 23.331 | 31.609 | **20.996** | n/a | n/a |
| `blake2b` | **43.726** | 64.723 | 68.915 | n/a | n/a |
| `sha512` | **47.147** | 50.542 | 49.484 | n/a | n/a |
| `x25519` | **44.302** | 48.310 | 49.217 | n/a | n/a |

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
| _(floor: empty program)_ | _3.659_ | _97.362_ | _**101.021**_ | _57.672_ | _77.277_ | _66.120_ |
| `lcg` | 3.823 | 108.673 | **112.496** | 58.282 | 84.909 | 65.044 |
| `packet_classifier` | 3.905 | 108.624 | **112.529** | 58.447 | 86.653 | 64.708 |
| `ring_write` | 4.104 | 109.693 | **113.797** | 60.187 | 88.414 | 66.924 |
| `histogram_bins` | 4.327 | 118.076 | **122.403** | 59.354 | 105.412 | 93.799 |
| `prefix_scan` | 4.290 | 110.845 | **115.135** | 59.633 | 93.847 | 69.256 |
| `binary_search` | 4.470 | 110.336 | **114.806** | 59.497 | 89.385 | 70.634 |
| `sort_window` | 4.766 | 113.238 | **118.004** | 59.911 | 99.485 | 75.696 |
| `bloom_filter` | 5.322 | 113.470 | **118.792** | 60.170 | 98.233 | 71.548 |
| `hash_join` | 9.473 | 261.047 | **270.520** | 64.165 | 215.881 | 116.790 |
| `sieve` | 4.594 | 110.128 | **114.722** | 60.165 | 99.286 | 78.600 |
| `fib` | 4.000 | 108.539 | **112.539** | 59.009 | 86.727 | 65.534 |
| `collatz` | 4.185 | 111.962 | **116.147** | 59.137 | 88.053 | 65.598 |
| `matmul` | 6.137 | 110.989 | **117.126** | 62.831 | 103.120 | 87.386 |
| `json_parse` | 50.898 | 477.819 | **528.717** | 107.411 | 155.967 | 163.464 |
| `nbody` | 7.034 | 130.586 | **137.620** | 62.473 | 123.771 | 102.254 |
| `chacha20` | 54.285 | 603.299 | **657.584** | 110.506 | 140.359 | 113.050 |
| `poly1305` | 35.607 | 253.419 | **289.026** | 91.652 | 137.555 | 128.316 |
| `blake2b` | 36.765 | 352.765 | **389.530** | 92.661 | 143.331 | 122.275 |
| `sha512` | 37.520 | 470.780 | **508.300** | 95.164 | 139.305 | 108.869 |
| `x25519` | 46.025 | 719.073 | **765.098** | 102.828 | 1211.460 | 498.909 |

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
