# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-13T05:03:37Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `c90eb2494c7890cd226c6ea5cfa51b4ab051cdcd` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38348994105 |
| NURL | `v0.72.0-13-gc90eb249` |
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
| _(floor: empty program)_ | _1.466_ | _1.436_ | _1.693_ | _24.251_ | _17.758_ |
| `lcg` | 39.211 | **39.097** | 39.405 | 1900.211 | 5148.019 |
| `packet_classifier` | 56.505 | **56.352** | 56.579 | 162.694 | 4301.865 |
| `ring_write` | 42.413 | **42.364** | 42.551 | 67.244 | 6465.738 |
| `histogram_bins` | **39.491** | 40.759 | 40.962 | 67.353 | 6287.396 |
| `prefix_scan` | **21.913** | 22.012 | 22.161 | 66.212 | 4692.415 |
| `binary_search` | 39.712 | **38.420** | 41.197 | 108.050 | 5975.814 |
| `sort_window` | **26.747** | 26.753 | 26.936 | 199.618 | 12203.022 |
| `bloom_filter` | **15.451** | 18.050 | 18.507 | 2838.368 | 7534.904 |
| `hash_join` | **26.568** | 28.034 | 29.538 | 3449.790 | 8225.134 |
| `sieve` | 20.837 | **20.394** | 20.468 | 69.722 | 3247.541 |
| `fib` | **25.390** | 29.949 | 30.285 | 133.229 | 1364.361 |
| `collatz` | 12.431 | **12.342** | 12.808 | 51.769 | 745.629 |
| `matmul` | **33.417** | 33.703 | 33.889 | 77.997 | 3146.912 |
| `json_parse` | **8.306** | 8.637 | 11.836 | 37.199 | 39.971 |
| `nbody` | **25.310** | 39.867 | 25.316 | 101.809 | 3218.513 |
| `chacha20` | **7.661** | 40.540 | 33.976 | n/a | n/a |
| `poly1305` | 23.640 | 31.913 | **21.223** | n/a | n/a |
| `blake2b` | **43.893** | 64.936 | 69.040 | n/a | n/a |
| `sha512` | **47.366** | 50.657 | 49.660 | n/a | n/a |
| `x25519` | **44.529** | 48.533 | 49.576 | n/a | n/a |

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
| _(floor: empty program)_ | _4.121_ | _106.678_ | _**110.799**_ | _63.177_ | _81.670_ | _63.207_ |
| `lcg` | 4.137 | 114.096 | **118.233** | 62.366 | 91.956 | 68.963 |
| `packet_classifier` | 4.364 | 116.574 | **120.938** | 62.761 | 93.893 | 71.437 |
| `ring_write` | 13.122 | 121.470 | **134.592** | 71.869 | 95.314 | 74.470 |
| `histogram_bins` | 13.017 | 127.133 | **140.150** | 73.419 | 113.154 | 80.668 |
| `prefix_scan` | 13.573 | 122.093 | **135.666** | 72.947 | 102.110 | 75.876 |
| `binary_search` | 13.219 | 119.979 | **133.198** | 73.803 | 97.525 | 76.939 |
| `sort_window` | 13.387 | 122.459 | **135.846** | 72.553 | 107.805 | 83.068 |
| `bloom_filter` | 13.844 | 121.750 | **135.594** | 72.845 | 103.703 | 77.282 |
| `hash_join` | 16.989 | 270.145 | **287.134** | 76.050 | 223.643 | 123.587 |
| `sieve` | 13.417 | 119.918 | **133.335** | 71.930 | 106.728 | 84.585 |
| `fib` | 4.528 | 116.385 | **120.913** | 61.881 | 92.420 | 71.118 |
| `collatz` | 4.478 | 117.735 | **122.213** | 62.561 | 93.318 | 67.827 |
| `matmul` | 14.533 | 120.450 | **134.983** | 73.084 | 109.309 | 90.272 |
| `json_parse` | 43.162 | 494.880 | **538.042** | 104.238 | 161.995 | 167.179 |
| `nbody` | 15.730 | 138.573 | **154.303** | 73.296 | 130.028 | 106.562 |
| `chacha20` | 47.031 | 629.509 | **676.540** | 107.160 | 144.562 | 117.366 |
| `poly1305` | 31.370 | 280.476 | **311.846** | 93.409 | 144.906 | 134.533 |
| `blake2b` | 32.633 | 363.752 | **396.385** | 92.507 | 150.251 | 126.514 |
| `sha512` | 33.074 | 484.135 | **517.209** | 94.131 | 143.532 | 117.296 |
| `x25519` | 39.763 | 733.866 | **773.629** | 100.790 | 1236.759 | 510.760 |

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
