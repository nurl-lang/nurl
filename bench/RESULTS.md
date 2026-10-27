# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-27T11:39:36Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `2a99287eda8b8a5255b92f6b0918c7398b774455` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40496998713 |
| NURL | `v0.78.0-49-g2a99287e` |
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
| _(floor: empty program)_ | _1.484_ | _1.450_ | _1.618_ | _22.105_ | _17.301_ |
| `lcg` | 39.145 | **38.928** | 39.201 | 1883.216 | 5215.801 |
| `packet_classifier` | 56.168 | **56.144** | 56.398 | 161.062 | 4429.671 |
| `ring_write` | **42.131** | 42.175 | 42.288 | 66.011 | 6344.026 |
| `histogram_bins` | **40.473** | 40.490 | 40.736 | 66.295 | 6031.757 |
| `prefix_scan` | **21.525** | 21.662 | 21.840 | 65.754 | 4662.252 |
| `binary_search` | 38.161 | **38.147** | 40.867 | 106.255 | 9019.658 |
| `sort_window` | **26.449** | 26.610 | 26.707 | 197.200 | 12773.334 |
| `bloom_filter` | **15.363** | 17.880 | 18.259 | 2856.457 | 8155.686 |
| `hash_join` | **27.005** | 27.890 | 29.253 | 3417.546 | 8586.263 |
| `sieve` | 18.575 | **17.713** | 17.979 | 66.839 | 4218.898 |
| `fib` | 29.793 | **29.735** | 29.999 | 131.650 | 1375.453 |
| `collatz` | 12.262 | **12.101** | 12.415 | 50.063 | 747.576 |
| `matmul` | 33.399 | **33.287** | 33.803 | 75.678 | 3885.828 |
| `json_parse` | **8.073** | 8.544 | 11.801 | 34.388 | 38.312 |
| `nbody` | 25.187 | 39.751 | **25.078** | 100.724 | 3102.918 |
| `chacha20` | **7.276** | 40.376 | 33.630 | n/a | n/a |
| `poly1305` | **11.671** | 31.742 | 21.110 | n/a | n/a |
| `blake2b` | **43.439** | 65.171 | 69.064 | n/a | n/a |
| `sha512` | **46.109** | 50.485 | 49.387 | n/a | n/a |
| `x25519` | **44.221** | 48.573 | 49.151 | n/a | n/a |

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
| _(floor: empty program)_ | _4.284_ | _114.829_ | _**119.113**_ | _61.666_ | _82.294_ | _53.516_ |
| `lcg` | 4.347 | 124.590 | **128.937** | 60.877 | 88.097 | 56.765 |
| `packet_classifier` | 4.532 | 126.636 | **131.168** | 62.517 | 90.913 | 57.921 |
| `ring_write` | 15.024 | 129.341 | **144.365** | 71.947 | 90.702 | 59.191 |
| `histogram_bins` | 15.048 | 130.167 | **145.215** | 73.157 | 108.616 | 66.349 |
| `prefix_scan` | 15.107 | 129.903 | **145.010** | 72.589 | 97.323 | 62.193 |
| `binary_search` | 15.186 | 130.153 | **145.339** | 73.636 | 92.552 | 63.958 |
| `sort_window` | 15.440 | 130.300 | **145.740** | 73.648 | 102.197 | 68.255 |
| `bloom_filter` | 16.098 | 133.740 | **149.838** | 74.631 | 102.445 | 66.212 |
| `hash_join` | 19.491 | 265.316 | **284.807** | 75.344 | 217.402 | 108.674 |
| `sieve` | 15.312 | 128.544 | **143.856** | 73.288 | 101.287 | 68.133 |
| `fib` | 4.574 | 125.562 | **130.136** | 61.113 | 88.517 | 57.636 |
| `collatz` | 4.710 | 128.668 | **133.378** | 63.101 | 91.744 | 57.960 |
| `matmul` | 16.615 | 129.743 | **146.358** | 73.847 | 105.116 | 77.990 |
| `json_parse` | 49.866 | 494.500 | **544.366** | 108.754 | 159.959 | 155.162 |
| `nbody` | 17.813 | 137.796 | **155.609** | 75.280 | 125.631 | 93.164 |
| `chacha20` | 56.958 | 756.371 | **813.329** | 114.283 | 140.665 | 104.155 |
| `poly1305` | 42.666 | 510.328 | **552.994** | 99.677 | 141.717 | 118.621 |
| `blake2b` | 38.441 | 377.471 | **415.912** | 96.679 | 146.648 | 113.584 |
| `sha512` | 38.715 | 472.876 | **511.591** | 95.417 | 137.348 | 99.681 |
| `x25519` | 38.766 | 828.387 | **867.153** | 95.868 | 1215.524 | 490.190 |

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
