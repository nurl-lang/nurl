# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-01T18:52:24Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366636 KiB |
| Commit | `ef1c03d08a4d2c32a6503914cc80153515463bb8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41338311303 |
| NURL | `v0.84.0` |
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
| _(floor: empty program)_ | _3.870_ | _3.807_ | _4.123_ | _30.690_ | _16.469_ |
| `lcg` | 41.912 | **41.694** | 41.998 | 1813.057 | 4975.073 |
| `packet_classifier` | 58.989 | **58.867** | 59.105 | 169.695 | 4077.949 |
| `ring_write` | 45.088 | **44.858** | 45.017 | 72.694 | 6080.278 |
| `histogram_bins` | **41.865** | 43.016 | 43.375 | 72.896 | 5660.791 |
| `prefix_scan` | 24.360 | **24.271** | 24.488 | 69.466 | 4088.869 |
| `binary_search` | 43.157 | **41.555** | 44.714 | 113.522 | 6378.234 |
| `sort_window` | 29.620 | **29.278** | 29.412 | 199.979 | 12067.966 |
| `bloom_filter` | **19.314** | 20.485 | 21.112 | 2871.993 | 6987.147 |
| `hash_join` | 29.126 | **29.002** | 31.970 | 3399.341 | 7624.805 |
| `sieve` | 27.765 | 27.307 | **27.223** | 75.989 | 3205.358 |
| `fib` | **27.855** | 32.384 | 32.820 | 137.728 | 1112.417 |
| `collatz` | 14.955 | **14.802** | 15.074 | 57.004 | 698.081 |
| `matmul` | 36.492 | 36.443 | **36.372** | 75.878 | 2888.008 |
| `json_parse` | **8.228** | 13.310 | 18.837 | 41.908 | 38.033 |
| `nbody` | **26.810** | 42.391 | 27.805 | 104.091 | 3115.256 |
| `chacha20` | **9.722** | 43.564 | 36.090 | n/a | n/a |
| `poly1305` | **13.901** | 34.676 | 23.736 | n/a | n/a |
| `blake2b` | **46.298** | 67.233 | 71.815 | n/a | n/a |
| `sha512` | 49.941 | **49.765** | 52.051 | n/a | n/a |
| `x25519` | **35.000** | 51.581 | 52.385 | n/a | n/a |

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
| _(floor: empty program)_ | _7.307_ | _131.041_ | _**138.348**_ | _68.729_ | _87.156_ | _68.967_ |
| `lcg` | 7.264 | 139.132 | **146.396** | 67.865 | 94.832 | 78.660 |
| `packet_classifier` | 7.480 | 140.234 | **147.714** | 69.151 | 101.341 | 76.444 |
| `ring_write` | 15.914 | 138.861 | **154.775** | 75.660 | 96.629 | 75.697 |
| `histogram_bins` | 16.121 | 141.217 | **157.338** | 76.782 | 140.795 | 82.971 |
| `prefix_scan` | 16.126 | 142.105 | **158.231** | 76.653 | 102.816 | 78.144 |
| `binary_search` | 16.704 | 141.790 | **158.494** | 78.829 | 96.902 | 81.403 |
| `sort_window` | 16.114 | 140.326 | **156.440** | 75.074 | 106.039 | 84.666 |
| `bloom_filter` | 16.925 | 145.000 | **161.925** | 77.391 | 107.816 | 83.085 |
| `hash_join` | 19.930 | 314.988 | **334.918** | 84.673 | 228.525 | 132.137 |
| `sieve` | 16.711 | 143.109 | **159.820** | 78.016 | 110.297 | 87.598 |
| `fib` | 7.329 | 135.533 | **142.862** | 66.433 | 96.568 | 75.987 |
| `collatz` | 7.764 | 141.061 | **148.825** | 69.878 | 97.192 | 76.573 |
| `matmul` | 16.900 | 143.551 | **160.451** | 78.283 | 113.368 | 99.297 |
| `json_parse` | 47.148 | 348.239 | **395.387** | 109.533 | 163.417 | 179.839 |
| `nbody` | 18.008 | 148.182 | **166.190** | 78.080 | 136.577 | 116.762 |
| `chacha20` | 68.824 | 727.887 | **796.711** | 131.565 | 147.607 | 125.357 |
| `poly1305` | 58.078 | 431.645 | **489.723** | 120.167 | 154.255 | 141.648 |
| `blake2b` | 37.503 | 350.277 | **387.780** | 98.195 | 149.916 | 133.623 |
| `sha512` | 35.818 | 471.813 | **507.631** | 97.802 | 146.556 | 122.739 |
| `x25519` | 52.266 | 1409.119 | **1461.385** | 112.487 | 1256.694 | 520.162 |

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
