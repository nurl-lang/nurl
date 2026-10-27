# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-27T15:03:55Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `a8f64496c30dcdbcd9d2441194723fe576b396e1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40526202123 |
| NURL | `v0.78.0-54-ga8f64496` |
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
| _(floor: empty program)_ | _1.448_ | _1.466_ | _1.655_ | _22.804_ | _16.908_ |
| `lcg` | 39.038 | **39.006** | 39.140 | 2031.520 | 5240.022 |
| `packet_classifier` | 56.307 | **56.152** | 56.421 | 162.431 | 4385.036 |
| `ring_write` | 42.210 | **42.102** | 42.432 | 64.823 | 6924.475 |
| `histogram_bins` | **40.547** | 40.553 | 40.805 | 65.598 | 5982.303 |
| `prefix_scan` | **21.490** | 21.653 | 21.805 | 65.707 | 4736.323 |
| `binary_search` | 38.094 | **38.067** | 40.846 | 107.588 | 6035.620 |
| `sort_window` | **26.538** | 26.571 | 26.796 | 198.552 | 12362.283 |
| `bloom_filter` | **15.306** | 17.812 | 18.366 | 2845.140 | 7499.376 |
| `hash_join` | **26.937** | 27.873 | 29.239 | 3412.644 | 8235.928 |
| `sieve` | 18.407 | **17.745** | 17.752 | 63.922 | 3485.451 |
| `fib` | 29.857 | **29.754** | 29.854 | 131.425 | 1390.954 |
| `collatz` | 12.298 | **12.207** | 12.443 | 49.204 | 745.135 |
| `matmul` | 33.409 | **33.354** | 33.402 | 75.537 | 3296.071 |
| `json_parse` | **8.185** | 8.606 | 11.819 | 35.468 | 38.400 |
| `nbody` | **25.204** | 39.618 | 25.220 | 99.935 | 3121.702 |
| `chacha20` | **7.334** | 41.932 | 33.572 | n/a | n/a |
| `poly1305` | **11.673** | 31.805 | 21.151 | n/a | n/a |
| `blake2b` | **43.549** | 65.067 | 68.883 | n/a | n/a |
| `sha512` | **47.035** | 50.421 | 49.484 | n/a | n/a |
| `x25519` | **44.142** | 48.479 | 49.162 | n/a | n/a |

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
| _(floor: empty program)_ | _4.340_ | _112.479_ | _**116.819**_ | _61.999_ | _76.692_ | _52.963_ |
| `lcg` | 4.515 | 123.902 | **128.417** | 60.667 | 87.187 | 58.019 |
| `packet_classifier` | 4.617 | 125.161 | **129.778** | 61.774 | 90.537 | 59.375 |
| `ring_write` | 15.284 | 128.930 | **144.214** | 72.296 | 89.750 | 60.593 |
| `histogram_bins` | 15.080 | 128.565 | **143.645** | 71.648 | 108.312 | 67.186 |
| `prefix_scan` | 15.461 | 129.881 | **145.342** | 72.508 | 96.157 | 63.563 |
| `binary_search` | 15.670 | 129.073 | **144.743** | 72.731 | 91.159 | 65.100 |
| `sort_window` | 15.663 | 131.729 | **147.392** | 73.546 | 101.668 | 70.138 |
| `bloom_filter` | 16.085 | 136.342 | **152.427** | 73.079 | 100.726 | 66.639 |
| `hash_join` | 19.763 | 263.827 | **283.590** | 75.090 | 217.644 | 111.057 |
| `sieve` | 15.708 | 128.676 | **144.384** | 72.530 | 100.505 | 71.360 |
| `fib` | 4.734 | 127.823 | **132.557** | 62.154 | 87.992 | 59.153 |
| `collatz` | 4.872 | 128.314 | **133.186** | 62.190 | 89.895 | 60.389 |
| `matmul` | 17.099 | 130.977 | **148.076** | 74.672 | 104.193 | 79.354 |
| `json_parse` | 50.246 | 488.819 | **539.065** | 107.175 | 160.305 | 156.161 |
| `nbody` | 18.065 | 135.887 | **153.952** | 75.833 | 126.026 | 96.327 |
| `chacha20` | 57.685 | 754.773 | **812.458** | 114.771 | 139.442 | 105.862 |
| `poly1305` | 43.306 | 511.058 | **554.364** | 99.448 | 141.678 | 121.328 |
| `blake2b` | 39.282 | 381.868 | **421.150** | 97.213 | 145.696 | 115.328 |
| `sha512` | 39.192 | 474.704 | **513.896** | 96.937 | 138.156 | 102.593 |
| `x25519` | 38.963 | 829.859 | **868.822** | 95.116 | 1212.996 | 490.945 |

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
