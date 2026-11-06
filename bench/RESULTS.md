# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-06T08:21:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16365628 KiB |
| Commit | `e4dc310aea725e920caa182cb072f5ad7bc81923` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42186374098 |
| NURL | `v0.89.0` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.2 |
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
| _(floor: empty program)_ | _2.842_ | _2.816_ | _2.943_ | _27.945_ | _13.740_ |
| `lcg` | 43.037 | **42.750** | 43.199 | 1424.870 | 4174.199 |
| `packet_classifier` | 71.797 | **70.651** | 71.016 | 179.066 | 3337.928 |
| `ring_write` | 46.395 | **46.364** | 46.980 | 72.917 | 5028.804 |
| `histogram_bins` | 43.798 | **43.699** | 43.718 | 73.755 | 4678.337 |
| `prefix_scan` | 26.446 | **24.866** | 24.932 | 71.227 | 3417.034 |
| `binary_search` | 42.425 | **34.530** | 43.546 | 118.579 | 5576.777 |
| `sort_window` | 42.423 | **41.639** | 42.944 | 187.201 | 10117.417 |
| `bloom_filter` | 16.096 | **15.940** | 16.097 | 2389.188 | 6207.419 |
| `hash_join` | 26.545 | **25.356** | 27.736 | 3036.649 | 6603.961 |
| `sieve` | 42.817 | **40.464** | 40.575 | 90.919 | 2600.328 |
| `fib` | **31.182** | 32.649 | 31.479 | 122.100 | 857.026 |
| `collatz` | 16.846 | **16.803** | 17.595 | 64.731 | 571.068 |
| `matmul` | 22.247 | **22.177** | 22.489 | 71.923 | 2468.083 |
| `json_parse` | **7.049** | 10.838 | 13.886 | 38.172 | 32.144 |
| `nbody` | **23.385** | 33.544 | 24.409 | 81.147 | 2207.589 |
| `chacha20` | **6.298** | 39.047 | 33.589 | n/a | n/a |
| `poly1305` | **11.744** | 36.333 | 24.715 | n/a | n/a |
| `blake2b` | **44.420** | 49.012 | 54.608 | n/a | n/a |
| `sha512` | 44.009 | **42.453** | 47.027 | n/a | n/a |
| `x25519` | **30.196** | 43.748 | 43.488 | n/a | n/a |

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
| _(floor: empty program)_ | _6.489_ | _110.898_ | _**117.387**_ | _59.765_ | _69.479_ | _62.736_ |
| `lcg` | 5.857 | 112.402 | **118.259** | 55.201 | 74.445 | 69.365 |
| `packet_classifier` | 6.625 | 127.488 | **134.113** | 55.993 | 74.018 | 65.763 |
| `ring_write` | 15.535 | 126.274 | **141.809** | 66.045 | 72.006 | 67.948 |
| `histogram_bins` | 15.631 | 130.370 | **146.001** | 72.949 | 130.275 | 76.856 |
| `prefix_scan` | 15.381 | 123.973 | **139.354** | 67.910 | 83.736 | 73.738 |
| `binary_search` | 16.008 | 121.590 | **137.598** | 66.906 | 80.915 | 71.423 |
| `sort_window` | 15.887 | 128.591 | **144.478** | 71.138 | 92.395 | 93.704 |
| `bloom_filter` | 15.790 | 122.606 | **138.396** | 67.477 | 85.022 | 73.388 |
| `hash_join` | 19.600 | 243.654 | **263.254** | 77.275 | 184.385 | 122.257 |
| `sieve` | 16.060 | 125.281 | **141.341** | 70.608 | 91.111 | 81.722 |
| `fib` | 6.902 | 118.723 | **125.625** | 58.617 | 77.536 | 67.690 |
| `collatz` | 7.121 | 124.165 | **131.286** | 59.015 | 78.908 | 67.864 |
| `matmul` | 15.355 | 117.928 | **133.283** | 64.461 | 87.758 | 92.460 |
| `json_parse` | 44.400 | 312.227 | **356.627** | 102.618 | 137.349 | 181.865 |
| `nbody` | 16.900 | 129.212 | **146.112** | 68.794 | 108.233 | 108.268 |
| `chacha20` | 60.532 | 642.988 | **703.520** | 119.244 | 121.136 | 117.546 |
| `poly1305` | 50.594 | 380.871 | **431.465** | 107.139 | 128.904 | 130.257 |
| `blake2b` | 34.258 | 315.526 | **349.784** | 92.482 | 128.822 | 127.322 |
| `sha512` | 33.663 | 407.180 | **440.843** | 91.354 | 119.256 | 112.177 |
| `x25519` | 47.884 | 1315.675 | **1363.559** | 107.055 | 1158.594 | 506.924 |

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
