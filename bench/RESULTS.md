# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-22T08:45:34Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16367520 KiB |
| Commit | `7e9f93c09e54f52621d961b3916553f6fd0b0e2e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39749267053 |
| NURL | `v0.77.1` |
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
| _(floor: empty program)_ | _1.547_ | _1.523_ | _1.704_ | _24.310_ | _17.928_ |
| `lcg` | 39.138 | **39.075** | 39.498 | 1912.566 | 5452.960 |
| `packet_classifier` | 56.411 | **56.365** | 56.562 | 162.498 | 4327.272 |
| `ring_write` | **42.620** | 42.840 | 42.649 | 73.742 | 6509.637 |
| `histogram_bins` | **40.841** | 40.884 | 41.072 | 68.428 | 6414.729 |
| `prefix_scan` | 21.873 | **21.795** | 22.183 | 68.532 | 4527.498 |
| `binary_search` | 38.570 | **38.555** | 41.257 | 107.919 | 6207.589 |
| `sort_window` | 26.871 | **26.763** | 27.089 | 198.452 | 11316.055 |
| `bloom_filter` | **15.420** | 17.999 | 18.564 | 2848.725 | 7338.520 |
| `hash_join` | **27.008** | 28.139 | 29.402 | 3441.320 | 8592.585 |
| `sieve` | 25.650 | **25.049** | 25.055 | 72.667 | 3518.474 |
| `fib` | **30.171** | 30.304 | 30.394 | 134.526 | 1364.916 |
| `collatz` | 12.384 | **12.378** | 12.548 | 51.059 | 743.617 |
| `matmul` | 34.107 | **33.754** | 34.436 | 77.892 | 3182.110 |
| `json_parse` | **8.479** | 8.871 | 12.043 | 38.049 | 40.848 |
| `nbody` | **25.401** | 40.070 | 25.599 | 103.023 | 3086.111 |
| `chacha20` | **7.858** | 42.517 | 35.024 | n/a | n/a |
| `poly1305` | 23.827 | 32.187 | **21.352** | n/a | n/a |
| `blake2b` | **43.827** | 65.385 | 69.390 | n/a | n/a |
| `sha512` | **47.292** | 50.835 | 50.015 | n/a | n/a |
| `x25519` | **44.405** | 48.974 | 49.662 | n/a | n/a |

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
| _(floor: empty program)_ | _4.789_ | _119.629_ | _**124.418**_ | _66.137_ | _88.419_ | _64.249_ |
| `lcg` | 4.785 | 129.800 | **134.585** | 66.691 | 95.713 | 73.292 |
| `packet_classifier` | 4.831 | 129.347 | **134.178** | 65.023 | 98.421 | 71.555 |
| `ring_write` | 14.036 | 132.796 | **146.832** | 75.516 | 98.809 | 74.712 |
| `histogram_bins` | 14.261 | 133.042 | **147.303** | 74.980 | 115.347 | 80.034 |
| `prefix_scan` | 14.007 | 131.031 | **145.038** | 74.710 | 103.498 | 77.617 |
| `binary_search` | 14.412 | 133.606 | **148.018** | 75.978 | 102.035 | 81.724 |
| `sort_window` | 14.604 | 134.919 | **149.523** | 76.115 | 112.593 | 87.166 |
| `bloom_filter` | 15.021 | 137.599 | **152.620** | 78.601 | 109.744 | 82.103 |
| `hash_join` | 18.821 | 278.324 | **297.145** | 81.459 | 227.632 | 126.625 |
| `sieve` | 14.443 | 132.544 | **146.987** | 75.391 | 120.300 | 117.159 |
| `fib` | 5.221 | 131.733 | **136.954** | 67.238 | 99.771 | 76.181 |
| `collatz` | 5.138 | 133.972 | **139.110** | 68.288 | 102.717 | 74.619 |
| `matmul` | 16.416 | 135.943 | **152.359** | 78.281 | 113.840 | 95.308 |
| `json_parse` | 49.265 | 514.421 | **563.686** | 113.114 | 172.157 | 178.426 |
| `nbody` | 17.094 | 145.498 | **162.592** | 78.652 | 135.331 | 111.946 |
| `chacha20` | 49.561 | 927.356 | **976.917** | 113.916 | 168.025 | 147.536 |
| `poly1305` | 33.727 | 297.993 | **331.720** | 98.348 | 152.852 | 139.369 |
| `blake2b` | 39.034 | 393.483 | **432.517** | 102.070 | 157.802 | 135.946 |
| `sha512` | 37.998 | 494.349 | **532.347** | 101.127 | 147.665 | 122.613 |
| `x25519` | 37.853 | 845.647 | **883.500** | 100.647 | 1252.619 | 522.337 |

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
