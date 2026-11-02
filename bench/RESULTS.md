# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-02T09:31:09Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `8ca9248ccd98280db329745e116d96333ab0e191` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41420678883 |
| NURL | `v0.84.0-16-g8ca9248c` |
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
| _(floor: empty program)_ | _3.380_ | _3.180_ | _3.575_ | _24.568_ | _13.028_ |
| `lcg` | 32.087 | **32.076** | 32.609 | 1181.265 | 2916.035 |
| `packet_classifier` | 44.968 | **44.653** | 44.764 | 138.298 | 2454.933 |
| `ring_write` | 31.939 | 31.824 | **31.727** | 56.760 | 3470.082 |
| `histogram_bins` | 32.089 | **31.925** | 32.182 | 56.017 | 3208.261 |
| `prefix_scan` | 18.852 | **18.560** | 18.580 | 52.858 | 2311.515 |
| `binary_search` | 17.418 | **17.261** | 18.256 | 76.477 | 3653.265 |
| `sort_window` | 22.572 | 22.251 | **22.187** | 140.960 | 7477.270 |
| `bloom_filter` | 10.885 | **10.745** | 10.922 | 1673.070 | 4121.482 |
| `hash_join` | 23.183 | **18.171** | 19.985 | 1962.561 | 4359.593 |
| `sieve` | 17.818 | **17.172** | 17.666 | 54.703 | 1753.179 |
| `fib` | 21.433 | 20.910 | **20.401** | 78.254 | 564.441 |
| `collatz` | 11.365 | **11.070** | 11.689 | 41.870 | 385.014 |
| `matmul` | **23.079** | 23.538 | 23.299 | 56.875 | 1757.647 |
| `json_parse` | **5.292** | 9.374 | 12.048 | 28.804 | 23.232 |
| `nbody` | **18.004** | 26.971 | 19.570 | 65.983 | 1408.074 |
| `chacha20` | **5.293** | 21.620 | 21.818 | n/a | n/a |
| `poly1305` | **8.028** | 28.426 | 17.718 | n/a | n/a |
| `blake2b` | **27.605** | 45.529 | 50.775 | n/a | n/a |
| `sha512` | 32.745 | **32.487** | 34.720 | n/a | n/a |
| `x25519` | **21.257** | 32.248 | 33.810 | n/a | n/a |

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
| _(floor: empty program)_ | _6.131_ | _105.441_ | _**111.572**_ | _57.915_ | _76.478_ | _58.403_ |
| `lcg` | 6.232 | 114.256 | **120.488** | 58.071 | 82.471 | 64.842 |
| `packet_classifier` | 6.303 | 111.708 | **118.011** | 56.946 | 83.274 | 64.405 |
| `ring_write` | 11.874 | 111.786 | **123.660** | 62.942 | 82.142 | 64.373 |
| `histogram_bins` | 12.289 | 119.883 | **132.172** | 64.613 | 109.494 | 69.918 |
| `prefix_scan` | 12.304 | 113.786 | **126.090** | 62.351 | 86.369 | 71.242 |
| `binary_search` | 11.508 | 108.114 | **119.622** | 59.874 | 80.467 | 66.442 |
| `sort_window` | 11.431 | 106.746 | **118.177** | 57.768 | 87.144 | 68.879 |
| `bloom_filter` | 12.170 | 113.079 | **125.249** | 60.527 | 88.352 | 67.364 |
| `hash_join` | 14.268 | 183.908 | **198.176** | 63.553 | 150.762 | 100.068 |
| `sieve` | 11.272 | 102.984 | **114.256** | 56.813 | 85.131 | 70.760 |
| `fib` | 6.141 | 107.417 | **113.558** | 54.751 | 80.989 | 61.619 |
| `collatz` | 5.997 | 104.974 | **110.971** | 52.618 | 79.877 | 63.712 |
| `matmul` | 11.714 | 106.273 | **117.987** | 58.800 | 84.857 | 80.103 |
| `json_parse` | 31.017 | 235.003 | **266.020** | 79.380 | 118.533 | 135.475 |
| `nbody` | 13.332 | 108.007 | **121.339** | 59.563 | 96.567 | 84.352 |
| `chacha20` | 40.425 | 436.391 | **476.816** | 89.328 | 110.045 | 98.242 |
| `poly1305` | 34.801 | 284.541 | **319.342** | 82.932 | 111.294 | 105.944 |
| `blake2b` | 28.484 | 234.724 | **263.208** | 81.459 | 111.037 | 103.681 |
| `sha512` | 23.808 | 299.441 | **323.249** | 72.772 | 108.664 | 95.509 |
| `x25519` | 32.786 | 854.662 | **887.448** | 79.811 | 750.622 | 360.876 |

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
