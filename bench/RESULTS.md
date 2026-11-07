# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-07T00:24:06Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `5ab35366b67fb4619867e1a648b2b02711a093b3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42317382224 |
| NURL | `v0.90.0` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.2 |
| Python | Python 3.14.4 |

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
| _(floor: empty program)_ | _3.450_ | _3.467_ | _3.662_ | _28.328_ | _15.512_ |
| `lcg` | 41.404 | **41.309** | 41.334 | 1812.668 | 4963.130 |
| `packet_classifier` | 58.513 | **58.341** | 58.671 | 168.858 | 4055.546 |
| `ring_write` | 44.487 | **44.288** | 44.629 | 71.206 | 6220.148 |
| `histogram_bins` | **42.002** | 42.889 | 43.205 | 75.035 | 5670.976 |
| `prefix_scan` | **23.809** | 23.925 | 24.064 | 69.476 | 4445.107 |
| `binary_search` | 41.648 | **40.305** | 42.894 | 111.263 | 5972.594 |
| `sort_window` | **28.800** | 28.809 | 29.069 | 199.167 | 11922.706 |
| `bloom_filter` | **18.890** | 20.014 | 20.513 | 2771.406 | 6964.151 |
| `hash_join` | 29.197 | **28.967** | 31.736 | 3458.171 | 7756.931 |
| `sieve` | 25.853 | **24.492** | 24.854 | 74.552 | 3444.427 |
| `fib` | **27.910** | 32.934 | 32.840 | 138.498 | 1153.652 |
| `collatz` | 14.553 | **14.491** | 14.771 | 56.137 | 714.429 |
| `matmul` | 35.567 | **35.456** | 35.566 | 76.627 | 3138.203 |
| `json_parse` | **8.357** | 13.729 | 19.110 | 40.514 | 37.378 |
| `nbody` | **26.245** | 41.904 | 27.535 | 105.496 | 3005.782 |
| `chacha20` | **9.898** | 44.406 | 36.002 | n/a | n/a |
| `poly1305` | **13.681** | 34.091 | 23.420 | n/a | n/a |
| `blake2b` | **45.880** | 66.885 | 71.359 | n/a | n/a |
| `sha512` | 49.866 | **49.735** | 51.758 | n/a | n/a |
| `x25519` | **34.821** | 50.999 | 51.596 | n/a | n/a |

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
| _(floor: empty program)_ | _6.862_ | _124.900_ | _**131.762**_ | _65.360_ | _88.574_ | _65.649_ |
| `lcg` | 7.136 | 136.395 | **143.531** | 66.929 | 95.941 | 74.722 |
| `packet_classifier` | 7.304 | 139.086 | **146.390** | 67.997 | 98.661 | 75.178 |
| `ring_write` | 15.714 | 137.860 | **153.574** | 74.415 | 96.407 | 74.973 |
| `histogram_bins` | 15.867 | 137.690 | **153.557** | 74.641 | 137.598 | 81.776 |
| `prefix_scan` | 15.997 | 141.101 | **157.098** | 75.450 | 102.561 | 78.851 |
| `binary_search` | 15.803 | 138.250 | **154.053** | 76.213 | 99.528 | 81.871 |
| `sort_window` | 16.023 | 141.435 | **157.458** | 76.097 | 112.075 | 86.992 |
| `bloom_filter` | 16.608 | 144.823 | **161.431** | 76.911 | 108.282 | 80.821 |
| `hash_join` | 20.177 | 269.334 | **289.511** | 79.394 | 220.557 | 128.335 |
| `sieve` | 16.188 | 140.967 | **157.155** | 76.439 | 109.966 | 88.435 |
| `fib` | 7.300 | 136.884 | **144.184** | 67.278 | 96.253 | 75.615 |
| `collatz` | 7.624 | 141.464 | **149.088** | 69.092 | 97.599 | 75.857 |
| `matmul` | 16.532 | 143.792 | **160.324** | 76.383 | 111.935 | 100.342 |
| `json_parse` | 46.793 | 351.519 | **398.312** | 108.992 | 162.973 | 178.064 |
| `nbody` | 17.975 | 147.204 | **165.179** | 78.131 | 130.498 | 111.879 |
| `chacha20` | 66.020 | 689.158 | **755.178** | 125.582 | 146.946 | 125.595 |
| `poly1305` | 54.728 | 417.858 | **472.586** | 115.328 | 153.369 | 140.198 |
| `blake2b` | 36.506 | 341.568 | **378.074** | 95.977 | 149.482 | 134.408 |
| `sha512` | 35.096 | 460.192 | **495.288** | 96.726 | 146.738 | 121.447 |
| `x25519` | 50.585 | 1403.790 | **1454.375** | 111.647 | 1239.851 | 515.674 |

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
