# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T19:00:03Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `3de7d9e0aa2fefbae448203c7c1a7445542cd6ae` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41110844688 |
| NURL | `v0.81.0-8-g3de7d9e0` |
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
| _(floor: empty program)_ | _3.260_ | _3.201_ | _3.535_ | _28.218_ | _15.188_ |
| `lcg` | 41.468 | **41.260** | 41.467 | 1801.055 | 4906.660 |
| `packet_classifier` | **58.552** | 58.693 | 58.971 | 170.824 | 4074.000 |
| `ring_write` | 44.644 | **44.255** | 44.632 | 71.670 | 6297.322 |
| `histogram_bins` | **41.937** | 42.833 | 43.012 | 71.753 | 5650.552 |
| `prefix_scan` | 24.050 | **23.769** | 23.856 | 69.397 | 4049.366 |
| `binary_search` | 41.455 | **40.133** | 43.306 | 109.527 | 5919.674 |
| `sort_window` | 29.090 | **28.755** | 28.969 | 198.252 | 11930.013 |
| `bloom_filter` | **18.646** | 20.294 | 20.548 | 2852.782 | 7020.739 |
| `hash_join` | 28.864 | **28.377** | 31.197 | 3363.838 | 7760.063 |
| `sieve` | **25.978** | 26.649 | 26.876 | 75.798 | 3202.555 |
| `fib` | **27.356** | 31.951 | 32.814 | 136.254 | 1094.824 |
| `collatz` | 14.418 | **14.166** | 14.507 | 53.946 | 689.555 |
| `matmul` | 35.851 | **35.756** | 36.027 | 74.330 | 2959.454 |
| `json_parse` | **10.130** | 13.053 | 18.740 | 41.038 | 37.254 |
| `nbody` | **26.158** | 41.904 | 27.460 | 104.204 | 6615.658 |
| `chacha20` | **9.147** | 44.409 | 36.094 | n/a | n/a |
| `poly1305` | **13.819** | 33.861 | 23.157 | n/a | n/a |
| `blake2b` | **46.279** | 67.284 | 71.349 | n/a | n/a |
| `sha512` | **49.616** | 49.903 | 51.595 | n/a | n/a |
| `x25519` | **33.876** | 51.481 | 51.859 | n/a | n/a |

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
| _(floor: empty program)_ | _6.812_ | _116.890_ | _**123.702**_ | _66.160_ | _82.482_ | _63.697_ |
| `lcg` | 6.860 | 127.223 | **134.083** | 65.574 | 91.590 | 72.099 |
| `packet_classifier` | 6.772 | 127.809 | **134.581** | 64.700 | 94.791 | 74.644 |
| `ring_write` | 17.070 | 131.817 | **148.887** | 76.304 | 95.798 | 74.816 |
| `histogram_bins` | 17.403 | 134.112 | **151.515** | 75.173 | 136.695 | 82.039 |
| `prefix_scan` | 17.557 | 129.409 | **146.966** | 75.948 | 98.664 | 76.657 |
| `binary_search` | 17.604 | 129.168 | **146.772** | 74.488 | 96.543 | 80.003 |
| `sort_window` | 17.993 | 131.603 | **149.596** | 75.931 | 106.501 | 84.159 |
| `bloom_filter` | 18.417 | 132.695 | **151.112** | 76.327 | 107.534 | 79.653 |
| `hash_join` | 21.750 | 268.558 | **290.308** | 80.574 | 219.913 | 128.453 |
| `sieve` | 17.782 | 127.582 | **145.364** | 75.548 | 106.292 | 86.946 |
| `fib` | 6.882 | 127.812 | **134.694** | 64.908 | 93.644 | 73.205 |
| `collatz` | 7.102 | 130.315 | **137.417** | 64.922 | 94.679 | 72.868 |
| `matmul` | 19.191 | 129.144 | **148.335** | 76.354 | 108.135 | 94.508 |
| `json_parse` | 52.936 | 460.700 | **513.636** | 113.103 | 162.365 | 180.045 |
| `nbody` | 20.327 | 137.084 | **157.411** | 77.955 | 129.134 | 112.958 |
| `chacha20` | 59.252 | 787.297 | **846.549** | 117.784 | 145.812 | 122.803 |
| `poly1305` | 46.728 | 512.076 | **558.804** | 106.442 | 150.043 | 137.494 |
| `blake2b` | 41.039 | 340.362 | **381.401** | 100.816 | 148.479 | 131.579 |
| `sha512` | 41.222 | 459.875 | **501.097** | 101.097 | 140.172 | 118.440 |
| `x25519` | 55.858 | 1554.865 | **1610.723** | 114.691 | 1252.351 | 513.812 |

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
