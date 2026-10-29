# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T00:17:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `4e570b4b6052675cbba55b806222715572cf03c7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40792392594 |
| NURL | `v0.80.0-20-g4e570b4b` |
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
| _(floor: empty program)_ | _1.342_ | _1.318_ | _1.520_ | _21.514_ | _15.052_ |
| `lcg` | **34.559** | 35.901 | 34.660 | 1442.393 | 4091.818 |
| `packet_classifier` | 49.609 | **49.523** | 49.706 | 127.524 | 3719.581 |
| `ring_write` | 37.309 | **37.217** | 37.509 | 60.764 | 6038.041 |
| `histogram_bins` | 34.974 | **34.894** | 35.100 | 62.099 | 4839.570 |
| `prefix_scan` | 19.284 | **19.247** | 19.514 | 58.751 | 3629.011 |
| `binary_search` | 32.584 | **28.045** | 33.904 | 90.657 | 5348.675 |
| `sort_window` | 23.576 | **23.554** | 23.735 | 131.850 | 8550.052 |
| `bloom_filter` | **13.684** | 14.776 | 16.300 | 2148.419 | 6038.210 |
| `hash_join` | **21.839** | 22.675 | 23.792 | 2653.699 | 6582.371 |
| `sieve` | 19.938 | **18.725** | 19.205 | 60.300 | 2677.224 |
| `fib` | **21.795** | 25.891 | 26.021 | 113.548 | 1001.527 |
| `collatz` | 10.715 | **10.677** | 10.967 | 43.638 | 590.241 |
| `matmul` | 35.456 | 35.356 | **35.267** | 67.815 | 2774.993 |
| `json_parse` | **6.353** | 7.014 | 9.559 | 31.871 | 30.934 |
| `nbody` | 20.990 | 35.080 | **20.957** | 76.639 | 2524.522 |
| `chacha20` | **6.828** | 35.861 | 27.759 | n/a | n/a |
| `poly1305` | **10.230** | 31.459 | 18.629 | n/a | n/a |
| `blake2b` | **38.384** | 55.711 | 60.870 | n/a | n/a |
| `sha512` | **38.756** | 40.355 | 42.428 | n/a | n/a |
| `x25519` | **27.774** | 42.193 | 43.634 | n/a | n/a |

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
| _(floor: empty program)_ | _4.520_ | _110.936_ | _**115.456**_ | _61.388_ | _80.608_ | _58.514_ |
| `lcg` | 4.362 | 118.359 | **122.721** | 60.747 | 88.447 | 66.091 |
| `packet_classifier` | 4.912 | 122.653 | **127.565** | 62.684 | 88.625 | 66.398 |
| `ring_write` | 13.528 | 121.914 | **135.442** | 69.744 | 90.254 | 67.935 |
| `histogram_bins` | 13.012 | 121.582 | **134.594** | 69.986 | 103.742 | 73.955 |
| `prefix_scan` | 13.599 | 121.735 | **135.334** | 70.038 | 94.680 | 69.684 |
| `binary_search` | 13.568 | 120.969 | **134.537** | 71.152 | 93.662 | 73.834 |
| `sort_window` | 13.785 | 122.961 | **136.746** | 69.765 | 100.352 | 79.204 |
| `bloom_filter` | 13.917 | 122.916 | **136.833** | 69.681 | 97.276 | 72.822 |
| `hash_join` | 16.639 | 217.464 | **234.103** | 72.421 | 180.728 | 109.420 |
| `sieve` | 13.522 | 117.740 | **131.262** | 71.001 | 98.136 | 76.119 |
| `fib` | 4.624 | 118.997 | **123.621** | 61.959 | 87.336 | 65.207 |
| `collatz` | 4.619 | 117.587 | **122.206** | 59.860 | 88.721 | 65.049 |
| `matmul` | 13.913 | 118.448 | **132.361** | 68.296 | 98.339 | 85.330 |
| `json_parse` | 40.149 | 366.148 | **406.297** | 97.321 | 142.003 | 148.426 |
| `nbody` | 14.953 | 123.249 | **138.202** | 69.383 | 112.882 | 96.209 |
| `chacha20` | 45.754 | 587.434 | **633.188** | 101.272 | 123.412 | 106.349 |
| `poly1305` | 34.803 | 410.612 | **445.415** | 92.611 | 128.367 | 117.655 |
| `blake2b` | 31.938 | 302.175 | **334.113** | 88.482 | 128.895 | 114.877 |
| `sha512` | 31.693 | 368.050 | **399.743** | 87.300 | 121.997 | 101.246 |
| `x25519` | 41.992 | 978.098 | **1020.090** | 97.723 | 944.129 | 408.287 |

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
