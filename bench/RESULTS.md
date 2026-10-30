# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T12:32:38Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `f3a53c895afc4ee40bec1cd9d8d23970bfc1d56e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41055380387 |
| NURL | `v0.80.0-122-gf3a53c89` |
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
| _(floor: empty program)_ | _3.758_ | _3.722_ | _4.018_ | _29.900_ | _16.716_ |
| `lcg` | 41.757 | **41.732** | 42.075 | 1806.243 | 4990.783 |
| `packet_classifier` | **58.837** | 58.890 | 59.270 | 169.500 | 4008.173 |
| `ring_write` | 44.869 | **44.861** | 45.219 | 72.815 | 6238.686 |
| `histogram_bins` | **42.204** | 43.200 | 43.433 | 73.809 | 5641.497 |
| `prefix_scan` | **24.344** | 24.399 | 24.593 | 70.375 | 4197.549 |
| `binary_search` | 42.417 | **41.016** | 43.713 | 111.899 | 6220.949 |
| `sort_window` | **29.146** | 29.155 | 29.478 | 201.133 | 11828.902 |
| `bloom_filter` | **19.420** | 20.784 | 21.227 | 2899.639 | 7003.819 |
| `hash_join` | 29.571 | **29.549** | 32.016 | 3394.479 | 7704.245 |
| `sieve` | 27.965 | **27.252** | 27.264 | 78.677 | 3114.734 |
| `fib` | **27.743** | 32.403 | 32.530 | 137.557 | 1142.729 |
| `collatz` | 14.991 | **14.933** | 15.156 | 58.080 | 701.372 |
| `matmul` | 36.630 | **36.420** | 36.961 | 77.204 | 2984.808 |
| `json_parse` | **11.061** | 13.831 | 19.583 | 42.224 | 38.786 |
| `nbody` | **26.789** | 42.471 | 28.080 | 106.825 | 2982.664 |
| `chacha20` | **9.692** | 43.919 | 36.529 | n/a | n/a |
| `poly1305` | **14.458** | 34.637 | 24.030 | n/a | n/a |
| `blake2b` | **46.636** | 67.642 | 71.782 | n/a | n/a |
| `sha512` | **49.991** | 50.097 | 52.119 | n/a | n/a |
| `x25519` | **34.223** | 51.411 | 53.160 | n/a | n/a |

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
| _(floor: empty program)_ | _6.965_ | _122.693_ | _**129.658**_ | _69.068_ | _86.846_ | _67.675_ |
| `lcg` | 7.179 | 133.544 | **140.723** | 68.883 | 96.621 | 75.654 |
| `packet_classifier` | 7.202 | 132.785 | **139.987** | 68.323 | 98.863 | 78.225 |
| `ring_write` | 17.534 | 135.118 | **152.652** | 79.489 | 100.090 | 76.763 |
| `histogram_bins` | 18.497 | 139.972 | **158.469** | 80.697 | 144.218 | 86.469 |
| `prefix_scan` | 17.987 | 137.128 | **155.115** | 78.969 | 104.957 | 82.046 |
| `binary_search` | 18.170 | 134.933 | **153.103** | 79.171 | 101.888 | 80.607 |
| `sort_window` | 18.223 | 137.005 | **155.228** | 78.858 | 111.455 | 88.840 |
| `bloom_filter` | 18.963 | 139.875 | **158.838** | 79.899 | 110.283 | 84.020 |
| `hash_join` | 22.528 | 280.020 | **302.548** | 83.720 | 228.755 | 133.810 |
| `sieve` | 18.418 | 133.998 | **152.416** | 79.155 | 112.414 | 90.650 |
| `fib` | 7.236 | 132.091 | **139.327** | 68.843 | 99.315 | 75.787 |
| `collatz` | 7.594 | 138.548 | **146.142** | 70.277 | 105.888 | 88.835 |
| `matmul` | 19.378 | 137.207 | **156.585** | 79.720 | 114.324 | 99.697 |
| `json_parse` | 54.490 | 472.618 | **527.108** | 118.397 | 166.633 | 185.290 |
| `nbody` | 21.095 | 146.132 | **167.227** | 82.676 | 136.446 | 114.961 |
| `chacha20` | 60.852 | 803.984 | **864.836** | 123.642 | 150.300 | 128.561 |
| `poly1305` | 47.404 | 519.953 | **567.357** | 109.873 | 154.428 | 145.582 |
| `blake2b` | 42.510 | 347.965 | **390.475** | 104.604 | 154.981 | 138.112 |
| `sha512` | 42.375 | 466.224 | **508.599** | 104.726 | 147.699 | 124.357 |
| `x25519` | 56.463 | 1569.902 | **1626.365** | 119.478 | 1281.272 | 527.018 |

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
