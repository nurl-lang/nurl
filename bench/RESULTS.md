# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T05:01:16Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `87143d2561c0b7dc29c49e971d5420b4932824f4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40820415936 |
| NURL | `v0.80.0-36-g87143d25` |
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
| _(floor: empty program)_ | _1.626_ | _1.577_ | _1.767_ | _24.156_ | _17.685_ |
| `lcg` | **39.348** | 39.349 | 39.544 | 1817.934 | 5119.386 |
| `packet_classifier` | **56.404** | 56.578 | 56.577 | 162.414 | 4490.518 |
| `ring_write` | 42.336 | **42.228** | 42.546 | 67.275 | 6359.472 |
| `histogram_bins` | **39.603** | 40.848 | 40.995 | 68.174 | 6289.226 |
| `prefix_scan` | 21.877 | **21.790** | 22.027 | 66.653 | 4611.058 |
| `binary_search` | 39.849 | **38.278** | 41.035 | 107.400 | 6287.766 |
| `sort_window` | **26.751** | 26.826 | 26.876 | 198.788 | 11507.869 |
| `bloom_filter` | **16.782** | 17.975 | 18.518 | 2865.204 | 7657.483 |
| `hash_join` | **27.102** | 27.961 | 29.507 | 3490.485 | 8274.085 |
| `sieve` | 23.437 | **22.612** | 25.076 | 72.169 | 3281.726 |
| `fib` | **25.191** | 29.876 | 30.060 | 133.253 | 1377.803 |
| `collatz` | **12.319** | 12.334 | 12.650 | 52.624 | 740.383 |
| `matmul` | 33.761 | **33.686** | 33.842 | 78.116 | 3166.030 |
| `json_parse` | **8.534** | 8.669 | 11.986 | 37.555 | 39.925 |
| `nbody` | **25.273** | 39.893 | 25.682 | 102.357 | 3130.834 |
| `chacha20` | **7.427** | 40.604 | 33.754 | n/a | n/a |
| `poly1305` | **11.947** | 32.042 | 21.328 | n/a | n/a |
| `blake2b` | **44.279** | 65.228 | 70.258 | n/a | n/a |
| `sha512` | **47.546** | 50.714 | 49.719 | n/a | n/a |
| `x25519` | **31.740** | 48.689 | 49.653 | n/a | n/a |

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
| _(floor: empty program)_ | _4.679_ | _123.897_ | _**128.576**_ | _67.405_ | _88.669_ | _66.072_ |
| `lcg` | 4.833 | 135.751 | **140.584** | 67.795 | 98.324 | 73.981 |
| `packet_classifier` | 4.885 | 132.465 | **137.350** | 65.500 | 96.616 | 75.335 |
| `ring_write` | 15.283 | 134.642 | **149.925** | 75.430 | 97.302 | 74.401 |
| `histogram_bins` | 15.690 | 138.800 | **154.490** | 77.568 | 115.889 | 80.768 |
| `prefix_scan` | 15.589 | 136.519 | **152.108** | 75.294 | 104.545 | 79.749 |
| `binary_search` | 15.797 | 134.746 | **150.543** | 76.325 | 97.828 | 79.711 |
| `sort_window` | 16.390 | 138.986 | **155.376** | 77.289 | 110.318 | 88.412 |
| `bloom_filter` | 16.587 | 140.774 | **157.361** | 77.294 | 106.480 | 81.628 |
| `hash_join` | 19.969 | 272.133 | **292.102** | 81.016 | 225.492 | 126.041 |
| `sieve` | 16.025 | 139.139 | **155.164** | 77.791 | 112.120 | 85.300 |
| `fib` | 4.928 | 133.392 | **138.320** | 66.830 | 95.847 | 71.722 |
| `collatz` | 5.140 | 138.359 | **143.499** | 68.704 | 99.749 | 75.195 |
| `matmul` | 17.250 | 138.479 | **155.729** | 78.481 | 114.084 | 97.815 |
| `json_parse` | 50.826 | 475.878 | **526.704** | 112.663 | 165.546 | 177.326 |
| `nbody` | 18.722 | 144.207 | **162.929** | 79.729 | 133.111 | 111.831 |
| `chacha20` | 57.982 | 757.440 | **815.422** | 119.994 | 149.145 | 124.431 |
| `poly1305` | 44.486 | 520.377 | **564.863** | 106.278 | 146.681 | 136.150 |
| `blake2b` | 39.570 | 379.863 | **419.433** | 102.261 | 154.423 | 131.502 |
| `sha512` | 39.470 | 476.018 | **515.488** | 100.869 | 143.684 | 118.675 |
| `x25519` | 53.667 | 1301.465 | **1355.132** | 114.678 | 1225.515 | 516.322 |

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
