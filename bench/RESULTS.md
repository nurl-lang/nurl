# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T10:01:22Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ed18daad17961708c87009c6a89f5befa7e5070d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41036930820 |
| NURL | `v0.80.0-115-ged18daad` |
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
| _(floor: empty program)_ | _1.544_ | _1.505_ | _1.706_ | _22.421_ | _17.366_ |
| `lcg` | **39.119** | 39.174 | 39.330 | 1818.840 | 5216.364 |
| `packet_classifier` | 56.241 | **56.226** | 56.514 | 161.288 | 4290.903 |
| `ring_write` | 42.293 | **42.276** | 42.452 | 66.465 | 6321.228 |
| `histogram_bins` | **39.543** | 40.683 | 40.873 | 67.034 | 6083.142 |
| `prefix_scan` | 21.761 | **21.732** | 21.919 | 64.927 | 4533.489 |
| `binary_search` | 39.874 | **38.385** | 40.965 | 107.605 | 6294.097 |
| `sort_window` | **26.646** | 26.692 | 26.835 | 198.173 | 11814.580 |
| `bloom_filter` | **16.727** | 17.916 | 18.345 | 2851.395 | 7587.800 |
| `hash_join` | **26.926** | 28.235 | 29.222 | 3482.958 | 8362.875 |
| `sieve` | 25.456 | **24.655** | 24.688 | 72.587 | 3227.651 |
| `fib` | **25.092** | 29.942 | 30.061 | 133.568 | 1375.380 |
| `collatz` | 12.398 | **12.240** | 12.469 | 51.564 | 784.047 |
| `matmul` | 33.706 | **33.513** | 33.755 | 76.676 | 4415.557 |
| `json_parse` | **8.523** | 8.654 | 11.912 | 36.351 | 38.436 |
| `nbody` | **25.143** | 39.731 | 25.341 | 102.785 | 3089.478 |
| `chacha20` | **7.418** | 42.181 | 33.624 | n/a | n/a |
| `poly1305` | **11.681** | 31.822 | 21.210 | n/a | n/a |
| `blake2b` | **43.916** | 65.051 | 69.325 | n/a | n/a |
| `sha512` | **47.477** | 50.602 | 49.548 | n/a | n/a |
| `x25519` | **31.658** | 48.629 | 49.495 | n/a | n/a |

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
| _(floor: empty program)_ | _4.732_ | _116.200_ | _**120.932**_ | _64.367_ | _83.966_ | _63.506_ |
| `lcg` | 4.812 | 130.621 | **135.433** | 64.357 | 93.259 | 70.482 |
| `packet_classifier` | 4.891 | 129.790 | **134.681** | 63.843 | 93.844 | 71.574 |
| `ring_write` | 15.387 | 131.865 | **147.252** | 73.290 | 95.289 | 73.433 |
| `histogram_bins` | 15.629 | 132.639 | **148.268** | 73.401 | 111.826 | 79.862 |
| `prefix_scan` | 15.702 | 133.151 | **148.853** | 73.262 | 100.768 | 75.614 |
| `binary_search` | 15.772 | 131.962 | **147.734** | 73.326 | 96.362 | 77.339 |
| `sort_window` | 15.856 | 135.027 | **150.883** | 73.202 | 107.057 | 83.425 |
| `bloom_filter` | 16.530 | 137.242 | **153.772** | 75.549 | 105.494 | 78.917 |
| `hash_join` | 20.188 | 268.252 | **288.440** | 78.246 | 225.494 | 123.509 |
| `sieve` | 15.942 | 132.533 | **148.475** | 73.960 | 105.756 | 85.018 |
| `fib` | 4.981 | 132.520 | **137.501** | 64.590 | 95.021 | 73.253 |
| `collatz` | 5.121 | 134.820 | **139.941** | 64.898 | 95.607 | 72.666 |
| `matmul` | 17.204 | 133.863 | **151.067** | 74.963 | 109.400 | 94.654 |
| `json_parse` | 51.041 | 481.186 | **532.227** | 110.344 | 164.403 | 175.539 |
| `nbody` | 18.261 | 138.813 | **157.074** | 76.639 | 130.805 | 110.790 |
| `chacha20` | 58.357 | 761.941 | **820.298** | 117.769 | 146.445 | 121.346 |
| `poly1305` | 44.343 | 518.653 | **562.996** | 104.252 | 146.388 | 135.707 |
| `blake2b` | 39.407 | 378.692 | **418.099** | 98.558 | 150.599 | 132.214 |
| `sha512` | 39.473 | 480.054 | **519.527** | 98.069 | 142.553 | 117.154 |
| `x25519` | 53.984 | 1296.544 | **1350.528** | 113.204 | 1226.065 | 512.243 |

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
