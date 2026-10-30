# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T14:27:44Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `78d1be4f1a8dfb573156a1dee914e25d99b6cf5f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41071151383 |
| NURL | `v0.81.0` |
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
| _(floor: empty program)_ | _3.387_ | _3.443_ | _3.611_ | _28.515_ | _15.408_ |
| `lcg` | **41.450** | 41.539 | 41.576 | 1792.441 | 5432.515 |
| `packet_classifier` | **58.710** | **58.710** | 58.748 | 168.008 | 4125.771 |
| `ring_write` | **44.588** | 44.643 | 44.855 | 72.893 | 6225.410 |
| `histogram_bins` | **41.665** | 42.902 | 43.086 | 71.587 | 5674.679 |
| `prefix_scan` | 24.064 | **23.678** | 23.988 | 68.330 | 4200.191 |
| `binary_search` | 41.713 | **40.554** | 43.099 | 110.899 | 5899.207 |
| `sort_window` | 28.859 | **28.852** | 28.893 | 198.880 | 11783.250 |
| `bloom_filter` | **19.032** | 19.982 | 20.591 | 2862.092 | 7188.121 |
| `hash_join` | 29.433 | **29.064** | 31.609 | 3369.661 | 7762.345 |
| `sieve` | 26.776 | **26.034** | 26.466 | 75.100 | 3124.077 |
| `fib` | **27.131** | 32.064 | 32.131 | 136.291 | 1121.571 |
| `collatz` | 14.341 | **14.066** | 14.375 | 53.981 | 698.879 |
| `matmul` | 35.986 | **35.479** | 35.981 | 76.056 | 2948.484 |
| `json_parse` | **10.357** | 13.204 | 18.365 | 41.098 | 37.157 |
| `nbody` | **26.350** | 42.065 | 27.535 | 104.052 | 2920.772 |
| `chacha20` | **9.339** | 44.649 | 35.871 | n/a | n/a |
| `poly1305` | **13.626** | 33.978 | 23.207 | n/a | n/a |
| `blake2b` | **46.225** | 67.135 | 71.525 | n/a | n/a |
| `sha512` | 49.812 | **49.789** | 52.049 | n/a | n/a |
| `x25519` | **33.838** | 51.258 | 51.560 | n/a | n/a |

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
| _(floor: empty program)_ | _6.568_ | _117.477_ | _**124.045**_ | _66.751_ | _84.696_ | _65.574_ |
| `lcg` | 6.979 | 128.804 | **135.783** | 66.089 | 92.418 | 73.224 |
| `packet_classifier` | 6.894 | 126.476 | **133.370** | 65.365 | 92.499 | 73.521 |
| `ring_write` | 17.254 | 130.951 | **148.205** | 75.772 | 96.407 | 75.460 |
| `histogram_bins` | 17.484 | 132.230 | **149.714** | 75.571 | 137.521 | 81.929 |
| `prefix_scan` | 17.543 | 130.433 | **147.976** | 75.434 | 101.105 | 78.016 |
| `binary_search` | 17.807 | 129.789 | **147.596** | 75.472 | 97.211 | 79.538 |
| `sort_window` | 18.212 | 134.895 | **153.107** | 78.302 | 106.905 | 86.665 |
| `bloom_filter` | 18.532 | 133.094 | **151.626** | 76.664 | 104.782 | 81.045 |
| `hash_join` | 23.260 | 275.143 | **298.403** | 82.401 | 224.840 | 131.454 |
| `sieve` | 17.635 | 128.616 | **146.251** | 76.094 | 106.547 | 87.042 |
| `fib` | 6.873 | 127.302 | **134.175** | 65.011 | 92.967 | 73.634 |
| `collatz` | 7.204 | 128.364 | **135.568** | 64.647 | 93.553 | 73.694 |
| `matmul` | 19.248 | 138.622 | **157.870** | 79.335 | 108.945 | 95.758 |
| `json_parse` | 53.325 | 459.279 | **512.604** | 113.616 | 163.277 | 178.588 |
| `nbody` | 20.233 | 137.171 | **157.404** | 77.966 | 133.280 | 114.455 |
| `chacha20` | 60.107 | 789.959 | **850.066** | 118.325 | 145.467 | 125.692 |
| `poly1305` | 45.838 | 513.128 | **558.966** | 105.089 | 149.729 | 138.077 |
| `blake2b` | 41.009 | 335.808 | **376.817** | 99.928 | 149.665 | 134.318 |
| `sha512` | 41.792 | 465.906 | **507.698** | 103.160 | 143.448 | 120.905 |
| `x25519` | 55.641 | 1550.863 | **1606.504** | 115.132 | 1252.127 | 515.962 |

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
