# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T09:25:35Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `409d3496306d6ccb7321c81f64af3f8a12b23a92` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41032584993 |
| NURL | `v0.80.0-113-g409d3496` |
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
| _(floor: empty program)_ | _1.638_ | _1.689_ | _1.861_ | _29.954_ | _19.570_ |
| `lcg` | 39.480 | **39.430** | 39.625 | 1818.034 | 5031.702 |
| `packet_classifier` | 56.505 | **56.450** | 56.639 | 162.173 | 4420.163 |
| `ring_write` | 42.473 | **42.270** | 42.602 | 68.736 | 6521.585 |
| `histogram_bins` | **39.550** | 40.745 | 41.052 | 66.812 | 5924.527 |
| `prefix_scan` | 21.906 | **21.904** | 22.067 | 66.963 | 4562.954 |
| `binary_search` | 40.093 | **38.584** | 41.120 | 109.483 | 6181.601 |
| `sort_window` | **26.739** | 26.763 | 26.915 | 199.371 | 11362.523 |
| `bloom_filter` | **16.826** | 18.083 | 18.659 | 2872.746 | 7761.609 |
| `hash_join` | **27.484** | 28.471 | 29.896 | 3516.447 | 8646.364 |
| `sieve` | 24.538 | **23.167** | 23.622 | 74.735 | 3295.217 |
| `fib` | **25.781** | 30.472 | 30.770 | 138.720 | 1362.804 |
| `collatz` | 12.761 | **12.701** | 12.999 | 55.236 | 748.308 |
| `matmul` | 34.085 | **33.934** | 34.379 | 81.804 | 3225.693 |
| `json_parse` | **8.922** | 9.319 | 12.341 | 41.273 | 41.708 |
| `nbody` | 25.686 | 40.125 | **25.621** | 103.525 | 3149.842 |
| `chacha20` | **7.418** | 40.857 | 34.010 | n/a | n/a |
| `poly1305` | **11.801** | 32.157 | 21.511 | n/a | n/a |
| `blake2b` | **44.469** | 65.097 | 69.367 | n/a | n/a |
| `sha512` | **48.273** | 50.835 | 49.906 | n/a | n/a |
| `x25519` | **31.985** | 48.977 | 49.805 | n/a | n/a |

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
| _(floor: empty program)_ | _4.898_ | _127.735_ | _**132.633**_ | _69.244_ | _95.167_ | _77.237_ |
| `lcg` | 5.365 | 144.729 | **150.094** | 71.353 | 110.341 | 80.105 |
| `packet_classifier` | 4.932 | 134.145 | **139.077** | 66.152 | 97.390 | 74.044 |
| `ring_write` | 16.251 | 141.051 | **157.302** | 78.523 | 101.786 | 78.362 |
| `histogram_bins` | 15.680 | 135.003 | **150.683** | 74.383 | 112.180 | 81.873 |
| `prefix_scan` | 15.843 | 139.404 | **155.247** | 76.609 | 105.411 | 77.765 |
| `binary_search` | 16.208 | 137.059 | **153.267** | 77.936 | 103.408 | 80.354 |
| `sort_window` | 16.378 | 141.301 | **157.679** | 78.593 | 112.518 | 84.204 |
| `bloom_filter` | 16.999 | 144.937 | **161.936** | 79.428 | 110.889 | 80.728 |
| `hash_join` | 20.807 | 280.498 | **301.305** | 83.821 | 231.060 | 132.515 |
| `sieve` | 16.187 | 139.478 | **155.665** | 78.681 | 114.305 | 92.200 |
| `fib` | 5.758 | 147.854 | **153.612** | 74.493 | 103.755 | 78.921 |
| `collatz` | 5.556 | 145.489 | **151.045** | 71.768 | 104.866 | 78.854 |
| `matmul` | 18.022 | 145.385 | **163.407** | 81.876 | 118.395 | 104.190 |
| `json_parse` | 55.331 | 515.792 | **571.123** | 121.232 | 174.636 | 187.531 |
| `nbody` | 19.304 | 152.213 | **171.517** | 82.946 | 139.887 | 115.392 |
| `chacha20` | 60.699 | 790.266 | **850.965** | 125.070 | 154.370 | 130.141 |
| `poly1305` | 46.637 | 538.996 | **585.633** | 113.393 | 154.530 | 144.396 |
| `blake2b` | 41.032 | 396.651 | **437.683** | 107.953 | 160.594 | 141.140 |
| `sha512` | 41.708 | 495.446 | **537.154** | 107.974 | 152.948 | 124.480 |
| `x25519` | 56.660 | 1336.207 | **1392.867** | 120.787 | 1263.558 | 529.364 |

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
