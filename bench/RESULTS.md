# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-21T02:02:55Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `60bd67c549f397e1c3c8f225dd3a262d9a760505` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39530387020 |
| NURL | `v0.76.0-2-g60bd67c5` |
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
| _(floor: empty program)_ | _1.186_ | _1.149_ | _1.318_ | _18.417_ | _12.422_ |
| `lcg` | 28.867 | **28.391** | 28.608 | 1093.853 | 2943.893 |
| `packet_classifier` | **40.566** | 40.696 | 40.943 | 127.585 | 2631.045 |
| `ring_write` | 29.281 | 28.782 | **28.567** | 51.474 | 3594.366 |
| `histogram_bins` | **28.355** | 28.429 | 29.463 | 50.245 | 3315.400 |
| `prefix_scan` | 15.751 | **15.614** | 15.822 | 50.888 | 2568.397 |
| `binary_search` | **14.646** | 14.721 | 15.441 | 69.289 | 3554.498 |
| `sort_window` | 22.105 | **19.664** | 20.692 | 131.834 | 6135.394 |
| `bloom_filter` | **8.627** | 8.758 | 8.930 | 1603.190 | 4249.248 |
| `hash_join` | **16.035** | 16.997 | 18.257 | 1927.711 | 4604.348 |
| `sieve` | 15.421 | **14.635** | 14.806 | 47.453 | 1821.561 |
| `fib` | **19.180** | 19.290 | 19.326 | 77.177 | 676.547 |
| `collatz` | 9.413 | **9.390** | 9.607 | 35.334 | 412.758 |
| `matmul` | 20.473 | 19.993 | **19.787** | 52.830 | 1677.451 |
| `json_parse` | **5.086** | 5.527 | 6.936 | 26.874 | 25.542 |
| `nbody` | **16.309** | 24.238 | 17.135 | 59.786 | 1490.173 |
| `chacha20` | **6.544** | 19.120 | 19.671 | n/a | n/a |
| `poly1305` | **15.370** | 27.129 | 15.748 | n/a | n/a |
| `blake2b` | **25.371** | 42.567 | 47.733 | n/a | n/a |
| `sha512` | **30.308** | 33.338 | 32.234 | n/a | n/a |
| `x25519` | **28.217** | 30.668 | 31.366 | n/a | n/a |

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
| _(floor: empty program)_ | _3.550_ | _89.154_ | _**92.704**_ | _53.545_ | _73.308_ | _51.932_ |
| `lcg` | 3.401 | 93.186 | **96.587** | 51.599 | 78.156 | 58.154 |
| `packet_classifier` | 3.628 | 93.039 | **96.667** | 51.500 | 77.662 | 58.973 |
| `ring_write` | 9.490 | 98.990 | **108.480** | 58.892 | 82.934 | 63.258 |
| `histogram_bins` | 9.182 | 98.182 | **107.364** | 56.576 | 88.754 | 65.257 |
| `prefix_scan` | 9.066 | 95.043 | **104.109** | 56.884 | 84.312 | 64.937 |
| `binary_search` | 9.277 | 96.947 | **106.224** | 57.379 | 79.726 | 62.594 |
| `sort_window` | 9.347 | 98.245 | **107.592** | 58.892 | 86.661 | 66.553 |
| `bloom_filter` | 9.597 | 97.351 | **106.948** | 57.349 | 87.619 | 65.987 |
| `hash_join` | 11.670 | 176.123 | **187.793** | 60.056 | 152.711 | 109.236 |
| `sieve` | 9.619 | 97.896 | **107.515** | 58.909 | 88.565 | 72.527 |
| `fib` | 3.446 | 86.662 | **90.108** | 47.122 | 76.264 | 58.161 |
| `collatz` | 3.677 | 89.015 | **92.692** | 49.058 | 74.051 | 59.323 |
| `matmul` | 9.746 | 89.331 | **99.077** | 53.707 | 80.213 | 74.286 |
| `json_parse` | 27.561 | 304.612 | **332.173** | 74.338 | 117.305 | 133.951 |
| `nbody` | 10.223 | 103.761 | **113.984** | 56.386 | 97.320 | 80.376 |
| `chacha20` | 26.466 | 491.968 | **518.434** | 74.357 | 102.506 | 93.228 |
| `poly1305` | 19.169 | 187.987 | **207.156** | 67.583 | 107.844 | 102.815 |
| `blake2b` | 22.328 | 253.058 | **275.386** | 72.265 | 111.582 | 100.661 |
| `sha512` | 21.526 | 299.463 | **320.989** | 71.822 | 104.448 | 90.866 |
| `x25519` | 23.811 | 442.494 | **466.305** | 71.635 | 745.720 | 332.388 |

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
