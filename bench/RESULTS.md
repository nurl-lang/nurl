# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-26T11:38:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `dd723d14e65474b6f8758f4fb1dee2c804952a18` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40315967217 |
| NURL | `v0.78.0-17-gdd723d14` |
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
| _(floor: empty program)_ | _1.180_ | _1.151_ | _1.317_ | _16.747_ | _11.642_ |
| `lcg` | 29.665 | **29.582** | 29.874 | 1122.183 | 3017.802 |
| `packet_classifier` | 42.436 | 42.662 | **42.403** | 129.597 | 2614.777 |
| `ring_write` | 30.138 | **29.986** | 30.315 | 48.758 | 3680.116 |
| `histogram_bins` | 29.520 | **29.255** | 29.484 | 48.101 | 3565.389 |
| `prefix_scan` | 15.750 | **15.450** | 16.257 | 44.016 | 2578.547 |
| `binary_search` | 14.580 | **14.575** | 15.262 | 65.056 | 3680.972 |
| `sort_window` | 20.462 | **20.435** | 20.733 | 135.082 | 6439.218 |
| `bloom_filter` | 8.838 | **8.836** | 9.052 | 1668.068 | 4441.075 |
| `hash_join` | **16.329** | 17.062 | 18.335 | 2017.581 | 4600.753 |
| `sieve` | 12.193 | **11.970** | 12.086 | 44.078 | 1808.957 |
| `fib` | 19.395 | **19.257** | 19.517 | 76.758 | 687.816 |
| `collatz` | 9.512 | **9.412** | 9.505 | 34.609 | 417.435 |
| `matmul` | **20.713** | 20.755 | 21.341 | 51.742 | 1904.838 |
| `json_parse` | **4.989** | 5.346 | 6.864 | 22.474 | 23.694 |
| `nbody` | **16.723** | 24.726 | 17.138 | 57.677 | 1472.277 |
| `chacha20` | **6.751** | 19.839 | 19.542 | n/a | n/a |
| `poly1305` | **8.653** | 26.875 | 15.332 | n/a | n/a |
| `blake2b` | **26.468** | 42.913 | 48.553 | n/a | n/a |
| `sha512` | **30.267** | 32.740 | 32.521 | n/a | n/a |
| `x25519` | **26.948** | 30.682 | 31.195 | n/a | n/a |

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
| _(floor: empty program)_ | _3.302_ | _81.897_ | _**85.199**_ | _46.598_ | _61.507_ | _41.422_ |
| `lcg` | 3.495 | 89.963 | **93.458** | 46.434 | 78.197 | 45.802 |
| `packet_classifier` | 3.476 | 90.239 | **93.715** | 46.515 | 68.765 | 46.273 |
| `ring_write` | 10.314 | 93.450 | **103.764** | 54.372 | 69.983 | 48.566 |
| `histogram_bins` | 10.182 | 95.772 | **105.954** | 54.814 | 79.258 | 52.426 |
| `prefix_scan` | 10.080 | 95.364 | **105.444** | 55.736 | 71.172 | 49.822 |
| `binary_search` | 10.264 | 94.341 | **104.605** | 53.400 | 70.328 | 50.441 |
| `sort_window` | 10.501 | 95.321 | **105.822** | 55.665 | 76.844 | 53.742 |
| `bloom_filter` | 10.549 | 95.591 | **106.140** | 54.208 | 75.754 | 51.597 |
| `hash_join` | 12.699 | 170.038 | **182.737** | 55.488 | 139.202 | 81.631 |
| `sieve` | 10.343 | 93.055 | **103.398** | 53.732 | 76.046 | 55.287 |
| `fib` | 3.563 | 88.519 | **92.082** | 45.958 | 66.346 | 46.295 |
| `collatz` | 3.702 | 92.669 | **96.371** | 46.922 | 68.595 | 49.553 |
| `matmul` | 11.023 | 93.659 | **104.682** | 54.313 | 76.787 | 61.142 |
| `json_parse` | 29.571 | 300.376 | **329.947** | 73.005 | 109.327 | 114.114 |
| `nbody` | 11.380 | 97.389 | **108.769** | 54.937 | 89.671 | 69.669 |
| `chacha20` | 32.990 | 491.156 | **524.146** | 75.851 | 95.819 | 77.645 |
| `poly1305` | 26.137 | 320.030 | **346.167** | 69.361 | 100.244 | 87.187 |
| `blake2b` | 23.772 | 236.972 | **260.744** | 67.052 | 102.586 | 85.164 |
| `sha512` | 23.950 | 294.685 | **318.635** | 67.318 | 98.234 | 75.552 |
| `x25519` | 23.189 | 495.551 | **518.740** | 66.390 | 731.537 | 317.119 |

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
