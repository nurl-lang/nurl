# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T13:57:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16367528 KiB |
| Commit | `acbfba84ace979f44d21daa39651d4c0b2723a56` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40885900026 |
| NURL | `v0.80.0-61-gacbfba84` |
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
| _(floor: empty program)_ | _1.280_ | _1.286_ | _1.479_ | _20.492_ | _14.221_ |
| `lcg` | 34.393 | **34.343** | 34.521 | 1418.410 | 4078.816 |
| `packet_classifier` | **49.312** | 49.340 | 49.522 | 122.512 | 3557.135 |
| `ring_write` | 37.053 | **36.990** | 37.150 | 58.542 | 5058.640 |
| `histogram_bins` | **34.631** | 34.734 | 34.805 | 58.932 | 4868.679 |
| `prefix_scan` | 19.050 | **18.994** | 19.191 | 57.631 | 3699.971 |
| `binary_search` | 32.350 | **27.710** | 33.602 | 88.715 | 5154.419 |
| `sort_window` | **23.297** | 23.380 | 23.498 | 130.076 | 8588.607 |
| `bloom_filter` | **13.547** | 14.592 | 16.099 | 2135.215 | 5933.670 |
| `hash_join` | **21.619** | 22.336 | 23.502 | 2776.389 | 6390.583 |
| `sieve` | 19.491 | 18.902 | **18.609** | 60.544 | 2664.479 |
| `fib` | **21.721** | 25.853 | 25.978 | 111.896 | 998.687 |
| `collatz` | 10.732 | **10.652** | 10.927 | 42.753 | 583.394 |
| `matmul` | **34.881** | 35.328 | 35.473 | 67.162 | 2617.993 |
| `json_parse` | **6.460** | 7.045 | 9.613 | 31.652 | 31.343 |
| `nbody` | 21.115 | 35.019 | **20.906** | 77.967 | 2523.465 |
| `chacha20` | **6.760** | 35.759 | 27.648 | n/a | n/a |
| `poly1305` | **10.147** | 31.338 | 18.640 | n/a | n/a |
| `blake2b` | **38.377** | 55.650 | 60.912 | n/a | n/a |
| `sha512` | **38.657** | 40.323 | 42.482 | n/a | n/a |
| `x25519` | **27.673** | 42.090 | 43.458 | n/a | n/a |

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
| _(floor: empty program)_ | _4.212_ | _102.862_ | _**107.074**_ | _59.539_ | _77.651_ | _54.202_ |
| `lcg` | 4.209 | 110.852 | **115.061** | 57.339 | 82.657 | 61.700 |
| `packet_classifier` | 4.334 | 112.275 | **116.609** | 57.899 | 83.985 | 62.157 |
| `ring_write` | 12.846 | 113.895 | **126.741** | 64.951 | 84.584 | 63.309 |
| `histogram_bins` | 12.912 | 113.860 | **126.772** | 65.561 | 97.429 | 70.777 |
| `prefix_scan` | 12.921 | 113.420 | **126.341** | 64.570 | 88.712 | 65.843 |
| `binary_search` | 13.319 | 114.074 | **127.393** | 66.441 | 86.549 | 67.356 |
| `sort_window` | 13.354 | 115.629 | **128.983** | 66.396 | 93.171 | 70.513 |
| `bloom_filter` | 13.537 | 116.634 | **130.171** | 65.836 | 90.847 | 68.439 |
| `hash_join` | 16.011 | 209.513 | **225.524** | 68.436 | 175.138 | 104.265 |
| `sieve` | 13.370 | 115.325 | **128.695** | 66.575 | 94.578 | 74.160 |
| `fib` | 4.414 | 114.685 | **119.099** | 59.107 | 84.254 | 63.220 |
| `collatz` | 4.601 | 117.941 | **122.542** | 60.082 | 87.509 | 64.661 |
| `matmul` | 14.215 | 117.159 | **131.374** | 68.254 | 95.937 | 81.636 |
| `json_parse` | 40.085 | 366.339 | **406.424** | 95.140 | 138.195 | 146.450 |
| `nbody` | 15.679 | 122.498 | **138.177** | 69.471 | 114.052 | 94.027 |
| `chacha20` | 45.483 | 584.843 | **630.326** | 100.577 | 122.952 | 102.637 |
| `poly1305` | 34.156 | 402.431 | **436.587** | 88.163 | 125.401 | 114.904 |
| `blake2b` | 31.060 | 299.103 | **330.163** | 86.523 | 127.306 | 112.275 |
| `sha512` | 31.314 | 368.982 | **400.296** | 86.383 | 120.886 | 100.476 |
| `x25519` | 41.936 | 979.599 | **1021.535** | 96.761 | 948.594 | 408.918 |

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
