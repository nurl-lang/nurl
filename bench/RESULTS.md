# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T06:36:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `8a77b4ef4d3391a9ebd909fc4de99e1d1cb3f145` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40644287643 |
| NURL | `v0.79.1-21-g8a77b4ef` |
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
| _(floor: empty program)_ | _1.473_ | _1.464_ | _1.639_ | _23.057_ | _17.538_ |
| `lcg` | **39.048** | 39.158 | 39.325 | 1912.923 | 5255.278 |
| `packet_classifier` | 56.407 | **56.353** | 56.408 | 162.563 | 4383.728 |
| `ring_write` | **42.233** | 42.261 | 42.492 | 65.945 | 6371.733 |
| `histogram_bins` | **39.662** | 40.833 | 41.062 | 70.444 | 6119.949 |
| `prefix_scan` | **21.782** | 21.883 | 22.057 | 66.569 | 4444.619 |
| `binary_search` | 39.793 | **38.414** | 41.062 | 108.073 | 6013.290 |
| `sort_window` | 26.685 | **26.524** | 27.032 | 197.996 | 11347.502 |
| `bloom_filter` | **16.572** | 17.855 | 18.429 | 2836.053 | 7551.426 |
| `hash_join` | **26.805** | 28.007 | 29.133 | 3406.592 | 8251.232 |
| `sieve` | 20.896 | **20.077** | 20.317 | 69.416 | 3134.963 |
| `fib` | **25.244** | 29.959 | 30.096 | 132.449 | 1357.132 |
| `collatz` | 12.292 | **12.276** | 12.601 | 52.898 | 739.136 |
| `matmul` | **33.645** | 33.646 | 33.766 | 76.854 | 3139.611 |
| `json_parse` | 8.648 | **8.533** | 11.890 | 37.147 | 40.056 |
| `nbody` | **25.285** | 39.827 | 25.553 | 104.530 | 3071.053 |
| `chacha20` | **7.402** | 40.557 | 33.847 | n/a | n/a |
| `poly1305` | **12.039** | 32.097 | 21.412 | n/a | n/a |
| `blake2b` | **43.937** | 65.171 | 69.438 | n/a | n/a |
| `sha512` | **47.516** | 50.679 | 49.699 | n/a | n/a |
| `x25519` | **44.624** | 48.587 | 49.417 | n/a | n/a |

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
| _(floor: empty program)_ | _4.673_ | _117.983_ | _**122.656**_ | _61.784_ | _78.643_ | _53.856_ |
| `lcg` | 4.600 | 126.543 | **131.143** | 61.883 | 90.051 | 58.698 |
| `packet_classifier` | 4.623 | 128.404 | **133.027** | 62.249 | 91.504 | 60.536 |
| `ring_write` | 15.366 | 129.438 | **144.804** | 72.295 | 91.382 | 60.148 |
| `histogram_bins` | 15.481 | 130.468 | **145.949** | 72.739 | 108.504 | 66.941 |
| `prefix_scan` | 15.524 | 135.245 | **150.769** | 74.735 | 100.383 | 63.815 |
| `binary_search` | 15.703 | 132.662 | **148.365** | 75.093 | 98.236 | 66.547 |
| `sort_window` | 15.901 | 133.488 | **149.389** | 73.318 | 105.748 | 70.004 |
| `bloom_filter` | 16.544 | 137.782 | **154.326** | 74.534 | 101.986 | 65.977 |
| `hash_join` | 20.006 | 266.985 | **286.991** | 77.577 | 218.349 | 110.672 |
| `sieve` | 15.686 | 132.161 | **147.847** | 74.441 | 104.641 | 71.397 |
| `fib` | 4.714 | 128.248 | **132.962** | 63.090 | 93.169 | 59.362 |
| `collatz` | 4.962 | 131.213 | **136.175** | 64.803 | 94.374 | 60.721 |
| `matmul` | 17.043 | 133.357 | **150.400** | 76.617 | 106.687 | 78.916 |
| `json_parse` | 51.630 | 496.886 | **548.516** | 111.457 | 163.293 | 157.995 |
| `nbody` | 18.593 | 139.653 | **158.246** | 77.613 | 129.633 | 95.808 |
| `chacha20` | 59.970 | 776.090 | **836.060** | 119.546 | 141.884 | 107.500 |
| `poly1305` | 45.877 | 525.810 | **571.687** | 106.895 | 146.994 | 123.536 |
| `blake2b` | 40.285 | 389.300 | **429.585** | 101.584 | 148.999 | 120.172 |
| `sha512` | 40.708 | 480.925 | **521.633** | 98.778 | 141.656 | 103.380 |
| `x25519` | 41.001 | 845.726 | **886.727** | 99.034 | 1241.471 | 497.285 |

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
