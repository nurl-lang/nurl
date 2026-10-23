# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-23T19:36:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `51bb3f9af0f89e5b18a3eac7a5f87c994292f279` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40011925629 |
| NURL | `v0.77.2-12-g51bb3f9a` |
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
| _(floor: empty program)_ | _1.619_ | _1.533_ | _1.821_ | _25.462_ | _18.968_ |
| `lcg` | 44.291 | **44.265** | 44.448 | 1821.394 | 5348.903 |
| `packet_classifier` | **63.442** | 63.465 | 63.743 | 159.075 | 4639.178 |
| `ring_write` | 47.718 | **47.670** | 47.786 | 74.416 | 6498.523 |
| `histogram_bins` | 44.705 | **44.700** | 44.979 | 76.484 | 6339.997 |
| `prefix_scan` | 24.658 | **24.400** | 24.708 | 72.997 | 4662.059 |
| `binary_search` | 36.439 | **35.791** | 43.370 | 112.395 | 7230.273 |
| `sort_window` | **30.091** | 30.096 | 30.380 | 166.120 | 11946.211 |
| `bloom_filter` | **17.341** | 18.784 | 20.793 | 2751.699 | 7842.590 |
| `hash_join` | **27.821** | 28.759 | 30.221 | 3455.519 | 8202.270 |
| `sieve` | 20.469 | **20.207** | 20.577 | 72.059 | 3562.018 |
| `fib` | 33.350 | **33.231** | 33.445 | 142.385 | 1287.683 |
| `collatz` | 13.755 | **13.684** | 13.876 | 54.301 | 758.009 |
| `matmul` | **45.328** | 46.209 | 45.991 | 84.571 | 3356.227 |
| `json_parse` | **7.922** | 8.753 | 12.433 | 39.218 | 40.563 |
| `nbody` | **26.918** | 45.006 | 26.956 | 97.672 | 3332.316 |
| `chacha20` | **9.007** | 45.983 | 35.602 | n/a | n/a |
| `poly1305` | 26.274 | 40.209 | **23.798** | n/a | n/a |
| `blake2b` | **48.462** | 73.200 | 78.119 | n/a | n/a |
| `sha512` | **49.685** | 51.837 | 54.485 | n/a | n/a |
| `x25519` | **49.334** | 54.037 | 55.725 | n/a | n/a |

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
| _(floor: empty program)_ | _4.914_ | _121.565_ | _**126.479**_ | _72.129_ | _92.049_ | _57.311_ |
| `lcg` | 5.154 | 134.262 | **139.416** | 69.275 | 100.056 | 62.573 |
| `packet_classifier` | 5.182 | 134.850 | **140.032** | 70.493 | 102.460 | 62.788 |
| `ring_write` | 15.115 | 138.755 | **153.870** | 80.328 | 104.596 | 65.999 |
| `histogram_bins` | 15.117 | 141.262 | **156.379** | 80.531 | 119.373 | 71.926 |
| `prefix_scan` | 15.022 | 140.206 | **155.228** | 80.974 | 110.483 | 68.412 |
| `binary_search` | 15.699 | 139.419 | **155.118** | 82.116 | 106.853 | 69.071 |
| `sort_window` | 15.491 | 141.382 | **156.873** | 80.833 | 115.333 | 75.014 |
| `bloom_filter` | 16.095 | 141.223 | **157.318** | 81.684 | 112.817 | 69.648 |
| `hash_join` | 19.018 | 269.053 | **288.071** | 84.724 | 218.480 | 115.256 |
| `sieve` | 15.462 | 141.973 | **157.435** | 81.945 | 114.132 | 75.743 |
| `fib` | 5.249 | 133.011 | **138.260** | 70.171 | 101.753 | 63.755 |
| `collatz` | 5.439 | 137.355 | **142.794** | 71.120 | 105.016 | 64.977 |
| `matmul` | 17.169 | 139.763 | **156.932** | 82.901 | 116.176 | 83.500 |
| `json_parse` | 49.403 | 482.274 | **531.677** | 115.468 | 178.773 | 163.719 |
| `nbody` | 17.351 | 146.606 | **163.957** | 81.323 | 135.162 | 99.722 |
| `chacha20` | 48.468 | 791.306 | **839.774** | 112.787 | 148.153 | 109.868 |
| `poly1305` | 33.155 | 282.212 | **315.367** | 97.452 | 150.529 | 123.941 |
| `blake2b` | 38.675 | 379.546 | **418.221** | 102.211 | 154.792 | 120.599 |
| `sha512` | 37.764 | 466.931 | **504.695** | 101.690 | 145.327 | 107.505 |
| `x25519` | 37.221 | 807.964 | **845.185** | 102.003 | 1200.796 | 499.878 |

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
