# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-24T04:43:36Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `08195640e69836dc5d2438681e18e2f76a945f86` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40063116813 |
| NURL | `v0.77.2-29-g08195640` |
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
| _(floor: empty program)_ | _1.103_ | _1.076_ | _1.196_ | _21.067_ | _13.815_ |
| `lcg` | 36.981 | 39.227 | **36.073** | 1460.291 | 3881.041 |
| `packet_classifier` | **60.887** | 61.621 | 61.221 | 154.124 | 3116.971 |
| `ring_write` | **38.969** | 39.951 | 39.469 | 61.067 | 4496.958 |
| `histogram_bins` | 38.295 | **36.015** | 36.507 | 61.849 | 4458.884 |
| `prefix_scan` | 20.359 | **19.639** | 20.588 | 58.086 | 3232.613 |
| `binary_search` | **27.623** | 28.353 | 36.139 | 99.343 | 4612.646 |
| `sort_window` | 35.792 | **34.928** | 35.869 | 163.910 | 8196.324 |
| `bloom_filter` | 13.791 | **12.388** | 12.586 | 2215.520 | 5831.764 |
| `hash_join` | **21.861** | 23.057 | 23.359 | 2718.791 | 6280.066 |
| `sieve` | **31.748** | 33.368 | 33.664 | 74.984 | 2430.207 |
| `fib` | 28.064 | 27.321 | **26.578** | 101.222 | 810.761 |
| `collatz` | **13.889** | 14.271 | 14.586 | 51.658 | 521.161 |
| `matmul` | 18.246 | **17.809** | 18.089 | 64.489 | 2282.475 |
| `json_parse` | **6.279** | 6.447 | 8.725 | 27.681 | 31.014 |
| `nbody` | **19.810** | 28.157 | 22.926 | 70.446 | 1959.098 |
| `chacha20` | **7.075** | 32.143 | 28.529 | n/a | n/a |
| `poly1305` | **11.260** | 31.192 | 20.135 | n/a | n/a |
| `blake2b` | **38.168** | 43.557 | 46.638 | n/a | n/a |
| `sha512` | **37.073** | 39.295 | 40.990 | n/a | n/a |
| `x25519` | 38.233 | 38.616 | **37.228** | n/a | n/a |

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
| _(floor: empty program)_ | _3.267_ | _82.708_ | _**85.975**_ | _46.379_ | _53.651_ | _45.116_ |
| `lcg` | 3.798 | 90.812 | **94.610** | 45.234 | 65.022 | 49.829 |
| `packet_classifier` | 3.840 | 93.490 | **97.330** | 46.671 | 67.531 | 52.484 |
| `ring_write` | 12.139 | 99.801 | **111.940** | 56.003 | 61.226 | 49.995 |
| `histogram_bins` | 12.267 | 92.917 | **105.184** | 54.423 | 74.180 | 56.374 |
| `prefix_scan` | 11.366 | 94.851 | **106.217** | 53.384 | 66.127 | 52.760 |
| `binary_search` | 12.702 | 94.446 | **107.148** | 53.875 | 63.261 | 54.903 |
| `sort_window` | 12.423 | 97.745 | **110.168** | 54.064 | 75.296 | 60.887 |
| `bloom_filter` | 12.349 | 96.694 | **109.043** | 53.122 | 64.843 | 53.539 |
| `hash_join` | 16.253 | 203.443 | **219.696** | 60.614 | 163.305 | 97.261 |
| `sieve` | 12.114 | 92.750 | **104.864** | 54.544 | 71.861 | 57.818 |
| `fib` | 3.759 | 91.026 | **94.785** | 46.553 | 59.714 | 49.178 |
| `collatz` | 4.124 | 93.015 | **97.139** | 46.466 | 60.057 | 50.287 |
| `matmul` | 13.962 | 93.505 | **107.467** | 54.500 | 71.431 | 65.997 |
| `json_parse` | 39.614 | 375.498 | **415.112** | 82.274 | 115.732 | 142.606 |
| `nbody` | 14.049 | 101.766 | **115.815** | 52.799 | 89.354 | 84.066 |
| `chacha20` | 43.304 | 640.624 | **683.928** | 86.134 | 97.823 | 87.151 |
| `poly1305` | 33.208 | 398.920 | **432.128** | 74.708 | 99.271 | 101.261 |
| `blake2b` | 29.706 | 300.750 | **330.456** | 72.074 | 104.403 | 102.390 |
| `sha512` | 30.882 | 373.258 | **404.140** | 74.999 | 95.787 | 87.534 |
| `x25519` | 29.733 | 811.300 | **841.033** | 76.136 | 1050.129 | 437.048 |

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
