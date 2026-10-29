# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T07:07:36Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16366504 KiB |
| Commit | `b4be26b0991b743103b9e6dbbd8e1f11cd37dcb6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40832808138 |
| NURL | `v0.80.0-42-gb4be26b0` |
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
| _(floor: empty program)_ | _1.251_ | _1.224_ | _1.370_ | _20.376_ | _14.632_ |
| `lcg` | **37.329** | 37.728 | 38.431 | 1400.745 | 3805.479 |
| `packet_classifier` | 64.951 | **64.392** | 64.705 | 160.738 | 3269.405 |
| `ring_write` | 41.130 | **41.065** | 41.929 | 63.623 | 4795.741 |
| `histogram_bins` | 39.265 | **38.864** | 39.464 | 65.970 | 4563.514 |
| `prefix_scan` | 21.346 | **21.026** | 21.593 | 65.367 | 3413.780 |
| `binary_search` | 37.520 | **30.711** | 39.609 | 109.647 | 4841.953 |
| `sort_window` | 38.002 | **37.872** | 38.935 | 172.834 | 8999.247 |
| `bloom_filter` | 13.770 | **13.356** | 13.777 | 2274.018 | 5890.241 |
| `hash_join` | **22.301** | 24.170 | 24.096 | 2816.390 | 6503.104 |
| `sieve` | 37.707 | **36.254** | 37.011 | 82.940 | 2563.224 |
| `fib` | **26.257** | 29.091 | 27.030 | 106.742 | 839.181 |
| `collatz` | **13.832** | 14.496 | 14.256 | 56.994 | 533.214 |
| `matmul` | 19.070 | **18.488** | 18.776 | 70.064 | 2395.900 |
| `json_parse` | **6.362** | 6.669 | 8.621 | 28.230 | 30.669 |
| `nbody` | 21.044 | 29.372 | **20.778** | 75.176 | 1987.533 |
| `chacha20` | **7.489** | 35.319 | 30.167 | n/a | n/a |
| `poly1305` | **12.269** | 32.273 | 21.362 | n/a | n/a |
| `blake2b` | **40.067** | 45.446 | 48.395 | n/a | n/a |
| `sha512` | **39.461** | 40.738 | 41.060 | n/a | n/a |
| `x25519` | **26.445** | 38.994 | 38.659 | n/a | n/a |

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
| _(floor: empty program)_ | _4.223_ | _95.326_ | _**99.549**_ | _52.934_ | _62.644_ | _53.022_ |
| `lcg` | 4.166 | 108.673 | **112.839** | 53.538 | 73.716 | 60.589 |
| `packet_classifier` | 4.295 | 104.765 | **109.060** | 52.047 | 71.385 | 60.636 |
| `ring_write` | 13.825 | 108.193 | **122.018** | 60.541 | 72.978 | 61.589 |
| `histogram_bins` | 14.403 | 113.074 | **127.477** | 62.235 | 91.564 | 69.312 |
| `prefix_scan` | 14.270 | 109.934 | **124.204** | 61.834 | 78.805 | 64.530 |
| `binary_search` | 14.268 | 110.332 | **124.600** | 62.649 | 75.823 | 67.116 |
| `sort_window` | 14.064 | 111.198 | **125.262** | 61.443 | 82.701 | 68.475 |
| `bloom_filter` | 14.600 | 114.711 | **129.311** | 63.696 | 85.777 | 66.051 |
| `hash_join` | 17.718 | 212.535 | **230.253** | 66.232 | 171.983 | 107.080 |
| `sieve` | 13.818 | 106.177 | **119.995** | 60.740 | 81.730 | 73.160 |
| `fib` | 4.257 | 105.851 | **110.108** | 54.398 | 74.530 | 60.002 |
| `collatz` | 4.369 | 106.685 | **111.054** | 53.090 | 73.666 | 59.822 |
| `matmul` | 15.055 | 108.197 | **123.252** | 61.580 | 83.147 | 82.868 |
| `json_parse` | 44.217 | 390.358 | **434.575** | 93.297 | 127.266 | 154.827 |
| `nbody` | 15.852 | 111.719 | **127.571** | 61.890 | 101.068 | 95.682 |
| `chacha20` | 49.785 | 630.917 | **680.702** | 98.271 | 114.583 | 105.782 |
| `poly1305` | 38.085 | 425.308 | **463.393** | 87.476 | 116.512 | 117.397 |
| `blake2b` | 34.794 | 320.127 | **354.921** | 84.552 | 122.678 | 114.921 |
| `sha512` | 34.892 | 385.254 | **420.146** | 83.102 | 112.773 | 100.024 |
| `x25519` | 46.190 | 1111.211 | **1157.401** | 94.906 | 1074.760 | 460.954 |

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
