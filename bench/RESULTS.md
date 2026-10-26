# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-26T18:42:12Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377684 KiB |
| Commit | `3d0afd1cf52bbb66b50f93a2365df422f6035751` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40379164400 |
| NURL | `v0.78.0-33-g3d0afd1c` |
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
| _(floor: empty program)_ | _1.435_ | _1.402_ | _1.601_ | _22.809_ | _16.939_ |
| `lcg` | **39.008** | 39.037 | 39.277 | 1897.698 | 5115.389 |
| `packet_classifier` | 56.282 | **56.120** | 56.347 | 163.320 | 4436.192 |
| `ring_write` | **42.057** | 42.123 | 42.319 | 64.777 | 6386.763 |
| `histogram_bins` | **40.562** | 40.602 | 40.807 | 67.283 | 6282.247 |
| `prefix_scan` | **21.494** | 21.578 | 21.784 | 64.898 | 4514.982 |
| `binary_search` | **38.015** | 38.153 | 40.887 | 106.538 | 6100.535 |
| `sort_window` | **26.612** | 26.616 | 26.772 | 197.872 | 11988.133 |
| `bloom_filter` | **15.277** | 17.729 | 18.225 | 2828.533 | 7823.408 |
| `hash_join` | **26.988** | 27.914 | 29.212 | 3537.279 | 8377.929 |
| `sieve` | 20.495 | **19.944** | 20.211 | 67.433 | 3331.762 |
| `fib` | **29.834** | 29.937 | 29.969 | 132.751 | 1363.340 |
| `collatz` | 12.256 | **12.240** | 12.503 | 50.139 | 740.310 |
| `matmul` | 33.491 | **33.361** | 33.555 | 76.093 | 3332.575 |
| `json_parse` | **8.080** | 8.593 | 11.657 | 35.143 | 38.742 |
| `nbody` | **25.211** | 39.639 | 25.247 | 100.963 | 3079.177 |
| `chacha20` | **7.252** | 41.048 | 33.697 | n/a | n/a |
| `poly1305` | **11.644** | 31.801 | 21.162 | n/a | n/a |
| `blake2b` | **43.655** | 64.862 | 68.787 | n/a | n/a |
| `sha512` | **46.344** | 50.547 | 49.429 | n/a | n/a |
| `x25519` | **44.348** | 48.598 | 49.403 | n/a | n/a |

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
| _(floor: empty program)_ | _4.510_ | _112.268_ | _**116.778**_ | _59.612_ | _76.618_ | _50.970_ |
| `lcg` | 4.299 | 120.704 | **125.003** | 59.916 | 88.940 | 56.593 |
| `packet_classifier` | 4.506 | 122.921 | **127.427** | 60.895 | 89.179 | 57.338 |
| `ring_write` | 15.088 | 125.151 | **140.239** | 71.428 | 91.757 | 58.739 |
| `histogram_bins` | 14.959 | 126.689 | **141.648** | 71.398 | 106.069 | 65.090 |
| `prefix_scan` | 15.103 | 126.938 | **142.041** | 71.040 | 94.742 | 61.267 |
| `binary_search` | 15.584 | 127.990 | **143.574** | 72.926 | 92.217 | 62.762 |
| `sort_window` | 15.291 | 128.376 | **143.667** | 71.665 | 100.353 | 67.574 |
| `bloom_filter` | 16.232 | 133.222 | **149.454** | 74.546 | 102.173 | 65.102 |
| `hash_join` | 19.657 | 264.305 | **283.962** | 76.848 | 215.323 | 109.108 |
| `sieve` | 15.676 | 127.005 | **142.681** | 73.010 | 104.011 | 68.740 |
| `fib` | 4.623 | 124.591 | **129.214** | 61.899 | 90.342 | 57.988 |
| `collatz` | 4.710 | 127.256 | **131.966** | 61.418 | 90.488 | 57.587 |
| `matmul` | 16.797 | 129.120 | **145.917** | 74.151 | 104.750 | 77.172 |
| `json_parse` | 49.970 | 489.093 | **539.063** | 107.650 | 159.875 | 154.715 |
| `nbody` | 17.925 | 136.951 | **154.876** | 75.006 | 127.153 | 93.121 |
| `chacha20` | 57.827 | 813.021 | **870.848** | 115.592 | 139.467 | 102.993 |
| `poly1305` | 43.136 | 509.043 | **552.179** | 100.914 | 140.645 | 119.081 |
| `blake2b` | 38.938 | 379.213 | **418.151** | 96.880 | 145.532 | 114.897 |
| `sha512` | 38.783 | 472.296 | **511.079** | 95.764 | 138.857 | 100.439 |
| `x25519` | 39.081 | 825.365 | **864.446** | 96.931 | 1216.091 | 489.791 |

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
