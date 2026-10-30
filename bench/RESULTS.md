# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T00:03:50Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `75e128a73076e8a1e4ae0fbfcff5e116d6f803ec` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40976570940 |
| NURL | `v0.80.0-84-g75e128a7` |
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
| _(floor: empty program)_ | _1.535_ | _1.506_ | _1.738_ | _23.538_ | _17.198_ |
| `lcg` | **39.057** | 39.072 | 39.274 | 1829.675 | 5142.943 |
| `packet_classifier` | 56.219 | **56.155** | 56.339 | 162.389 | 4444.765 |
| `ring_write` | **42.165** | 43.084 | 42.365 | 68.133 | 6367.117 |
| `histogram_bins` | **39.726** | 40.788 | 41.010 | 69.468 | 6184.493 |
| `prefix_scan` | 21.841 | **21.791** | 22.012 | 68.386 | 4770.590 |
| `binary_search` | 40.154 | **38.620** | 41.058 | 110.943 | 6038.818 |
| `sort_window` | **26.876** | 26.974 | 27.143 | 200.020 | 11615.866 |
| `bloom_filter` | **16.634** | 17.835 | 18.425 | 2880.468 | 7729.205 |
| `hash_join` | **26.971** | 27.968 | 29.383 | 3507.462 | 8256.637 |
| `sieve` | 23.674 | **21.814** | 22.340 | 71.107 | 3352.244 |
| `fib` | **25.328** | 29.913 | 30.196 | 137.913 | 1364.739 |
| `collatz` | 12.403 | **12.320** | 12.479 | 51.893 | 739.325 |
| `matmul` | **33.599** | 33.611 | 33.739 | 77.004 | 3222.447 |
| `json_parse` | **8.464** | 8.856 | 11.920 | 38.361 | 41.429 |
| `nbody` | **25.305** | 39.793 | 25.447 | 103.930 | 3122.723 |
| `chacha20` | **7.318** | 40.835 | 34.026 | n/a | n/a |
| `poly1305` | **11.613** | 32.020 | 21.278 | n/a | n/a |
| `blake2b` | **44.250** | 65.170 | 69.349 | n/a | n/a |
| `sha512` | **47.639** | 50.714 | 49.699 | n/a | n/a |
| `x25519` | **31.852** | 48.988 | 49.741 | n/a | n/a |

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
| _(floor: empty program)_ | _4.624_ | _117.041_ | _**121.665**_ | _64.884_ | _81.389_ | _62.225_ |
| `lcg` | 4.777 | 129.837 | **134.614** | 63.689 | 93.803 | 70.258 |
| `packet_classifier` | 4.939 | 130.148 | **135.087** | 64.536 | 94.350 | 72.222 |
| `ring_write` | 15.387 | 131.581 | **146.968** | 72.999 | 93.619 | 74.042 |
| `histogram_bins` | 15.648 | 134.446 | **150.094** | 74.636 | 114.116 | 83.341 |
| `prefix_scan` | 15.994 | 138.665 | **154.659** | 78.677 | 105.524 | 79.848 |
| `binary_search` | 15.760 | 133.888 | **149.648** | 75.598 | 100.122 | 80.037 |
| `sort_window` | 16.087 | 140.873 | **156.960** | 77.475 | 111.036 | 86.417 |
| `bloom_filter` | 16.757 | 141.295 | **158.052** | 78.057 | 109.158 | 81.088 |
| `hash_join` | 20.418 | 273.504 | **293.922** | 81.793 | 228.210 | 124.150 |
| `sieve` | 16.062 | 135.773 | **151.835** | 76.102 | 112.252 | 86.903 |
| `fib` | 5.095 | 135.030 | **140.125** | 66.873 | 96.502 | 73.982 |
| `collatz` | 5.204 | 137.955 | **143.159** | 67.773 | 98.879 | 73.516 |
| `matmul` | 17.420 | 135.865 | **153.285** | 76.404 | 111.811 | 96.998 |
| `json_parse` | 52.142 | 484.968 | **537.110** | 113.710 | 169.465 | 178.713 |
| `nbody` | 18.989 | 146.175 | **165.164** | 80.691 | 136.120 | 113.644 |
| `chacha20` | 59.048 | 775.070 | **834.118** | 120.425 | 147.568 | 123.627 |
| `poly1305` | 45.937 | 528.372 | **574.309** | 108.878 | 148.539 | 139.184 |
| `blake2b` | 39.633 | 382.539 | **422.172** | 99.888 | 153.672 | 134.867 |
| `sha512` | 39.844 | 482.512 | **522.356** | 101.170 | 148.503 | 122.201 |
| `x25519` | 55.948 | 1311.166 | **1367.114** | 118.796 | 1234.384 | 521.921 |

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
