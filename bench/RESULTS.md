# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T11:44:18Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `19ba7c74e448bad968f518f3b81c13cc39f98625` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41196935488 |
| NURL | `v0.82.0-33-g19ba7c74` |
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
| _(floor: empty program)_ | _3.491_ | _3.419_ | _3.628_ | _28.048_ | _15.887_ |
| `lcg` | 41.349 | **40.955** | 41.389 | 1787.101 | 4953.852 |
| `packet_classifier` | **58.328** | 58.419 | 58.371 | 167.756 | 4082.300 |
| `ring_write` | 44.526 | **44.450** | 44.482 | 70.486 | 6200.749 |
| `histogram_bins` | **41.762** | 42.667 | 42.891 | 70.642 | 5665.499 |
| `prefix_scan` | 23.945 | **23.711** | 24.033 | 69.895 | 4145.504 |
| `binary_search` | 42.317 | **40.482** | 43.247 | 111.516 | 5841.926 |
| `sort_window` | **28.975** | 29.060 | 29.107 | 201.331 | 12207.940 |
| `bloom_filter` | **18.701** | 19.867 | 20.441 | 2852.532 | 7326.879 |
| `hash_join` | 29.031 | **28.867** | 31.590 | 3360.001 | 7736.885 |
| `sieve` | 26.869 | **26.036** | 26.403 | 75.068 | 3271.083 |
| `fib` | **27.253** | 31.878 | 31.857 | 135.429 | 1108.266 |
| `collatz` | 14.597 | **14.317** | 14.602 | 55.316 | 688.156 |
| `matmul` | 35.703 | **35.545** | 35.854 | 74.728 | 2976.894 |
| `json_parse` | **10.388** | 13.195 | 18.588 | 39.660 | 36.718 |
| `nbody` | **26.242** | 41.821 | 27.366 | 105.955 | 2936.539 |
| `chacha20` | **9.598** | 44.450 | 35.765 | n/a | n/a |
| `poly1305` | **13.648** | 33.807 | 23.222 | n/a | n/a |
| `blake2b` | **46.301** | 67.114 | 71.374 | n/a | n/a |
| `sha512` | **49.759** | 49.857 | 51.689 | n/a | n/a |
| `x25519` | **33.601** | 51.214 | 51.558 | n/a | n/a |

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
| _(floor: empty program)_ | _7.088_ | _128.222_ | _**135.310**_ | _70.927_ | _86.786_ | _67.341_ |
| `lcg` | 6.965 | 137.076 | **144.041** | 68.085 | 95.983 | 75.419 |
| `packet_classifier` | 7.107 | 133.356 | **140.463** | 67.008 | 95.151 | 76.447 |
| `ring_write` | 16.555 | 132.766 | **149.321** | 74.280 | 93.382 | 76.389 |
| `histogram_bins` | 16.996 | 137.938 | **154.934** | 78.469 | 140.751 | 85.157 |
| `prefix_scan` | 16.975 | 136.919 | **153.894** | 74.815 | 102.561 | 79.071 |
| `binary_search` | 17.510 | 140.486 | **157.996** | 78.863 | 97.641 | 84.980 |
| `sort_window` | 17.240 | 140.323 | **157.563** | 77.214 | 111.258 | 89.288 |
| `bloom_filter` | 18.054 | 139.779 | **157.833** | 75.841 | 107.384 | 84.221 |
| `hash_join` | 20.819 | 272.956 | **293.775** | 79.684 | 222.369 | 128.073 |
| `sieve` | 16.743 | 132.985 | **149.728** | 75.271 | 107.008 | 87.823 |
| `fib` | 7.113 | 132.440 | **139.553** | 64.020 | 92.717 | 74.570 |
| `collatz` | 7.110 | 133.869 | **140.979** | 64.842 | 94.710 | 75.695 |
| `matmul` | 17.843 | 135.743 | **153.586** | 74.504 | 109.357 | 98.569 |
| `json_parse` | 51.044 | 463.206 | **514.250** | 110.778 | 160.094 | 178.822 |
| `nbody` | 19.263 | 147.776 | **167.039** | 82.386 | 131.468 | 114.120 |
| `chacha20` | 59.399 | 755.973 | **815.372** | 117.484 | 144.782 | 126.002 |
| `poly1305` | 47.084 | 514.161 | **561.245** | 105.722 | 150.476 | 139.704 |
| `blake2b` | 39.621 | 340.376 | **379.997** | 100.192 | 147.164 | 134.602 |
| `sha512` | 39.721 | 465.419 | **505.140** | 102.563 | 144.324 | 121.101 |
| `x25519` | 54.884 | 1562.107 | **1616.991** | 113.820 | 1252.138 | 516.341 |

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
