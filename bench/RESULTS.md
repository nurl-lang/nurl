# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-22T11:01:22Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `d48a99d0753208d843ca89c9689e0afd8cbfca74` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39766623704 |
| NURL | `v0.77.2` |
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
| _(floor: empty program)_ | _1.291_ | _1.291_ | _1.464_ | _22.286_ | _14.110_ |
| `lcg` | 34.388 | **34.250** | 34.369 | 1411.536 | 4115.041 |
| `packet_classifier` | 49.430 | **49.333** | 49.510 | 123.893 | 3726.243 |
| `ring_write` | 37.053 | **36.973** | 37.184 | 58.383 | 5232.394 |
| `histogram_bins` | 34.674 | **34.624** | 34.959 | 59.960 | 4751.206 |
| `prefix_scan` | 19.091 | **19.034** | 19.133 | 56.899 | 3807.449 |
| `binary_search` | 28.124 | **27.775** | 33.660 | 87.532 | 4901.458 |
| `sort_window` | 23.343 | **23.317** | 23.487 | 128.469 | 9306.117 |
| `bloom_filter` | **13.541** | 14.561 | 16.243 | 2158.673 | 6149.112 |
| `hash_join` | **21.597** | 22.251 | 23.540 | 2688.563 | 6249.029 |
| `sieve` | 19.640 | **18.674** | 18.996 | 59.611 | 2659.292 |
| `fib` | **25.847** | 26.034 | 26.051 | 112.834 | 1005.388 |
| `collatz` | 10.899 | **10.638** | 10.819 | 42.057 | 588.420 |
| `matmul` | **34.732** | 35.026 | 36.184 | 67.316 | 2687.776 |
| `json_parse` | **6.348** | 6.995 | 9.494 | 31.242 | 31.349 |
| `nbody` | 21.149 | 34.961 | **20.888** | 75.956 | 2492.768 |
| `chacha20` | **7.095** | 35.868 | 27.658 | n/a | n/a |
| `poly1305` | 20.461 | 31.302 | **18.753** | n/a | n/a |
| `blake2b` | **37.702** | 55.754 | 60.647 | n/a | n/a |
| `sha512` | **38.773** | 40.323 | 42.339 | n/a | n/a |
| `x25519` | **38.308** | 41.990 | 43.528 | n/a | n/a |

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
| _(floor: empty program)_ | _4.076_ | _102.374_ | _**106.450**_ | _57.911_ | _74.608_ | _54.798_ |
| `lcg` | 4.070 | 104.867 | **108.937** | 55.580 | 81.779 | 61.418 |
| `packet_classifier` | 4.182 | 108.097 | **112.279** | 56.954 | 81.613 | 61.417 |
| `ring_write` | 11.567 | 109.553 | **121.120** | 63.769 | 82.701 | 62.981 |
| `histogram_bins` | 11.664 | 109.205 | **120.869** | 64.404 | 95.288 | 70.000 |
| `prefix_scan` | 11.632 | 110.845 | **122.477** | 63.961 | 86.796 | 65.847 |
| `binary_search` | 11.949 | 110.093 | **122.042** | 65.370 | 83.152 | 67.689 |
| `sort_window` | 11.989 | 110.762 | **122.751** | 63.897 | 93.685 | 72.116 |
| `bloom_filter` | 12.249 | 111.819 | **124.068** | 65.751 | 92.244 | 68.458 |
| `hash_join` | 14.908 | 211.092 | **226.000** | 67.845 | 175.525 | 105.856 |
| `sieve` | 11.889 | 110.541 | **122.430** | 65.905 | 93.787 | 72.964 |
| `fib` | 4.274 | 105.826 | **110.100** | 56.550 | 83.522 | 63.152 |
| `collatz` | 4.318 | 109.270 | **113.588** | 57.623 | 83.005 | 62.719 |
| `matmul` | 13.126 | 110.640 | **123.766** | 66.684 | 95.787 | 84.526 |
| `json_parse` | 36.959 | 377.330 | **414.289** | 90.024 | 131.804 | 146.293 |
| `nbody` | 13.969 | 124.452 | **138.421** | 67.848 | 111.404 | 94.687 |
| `chacha20` | 36.923 | 643.926 | **680.849** | 89.880 | 118.377 | 103.368 |
| `poly1305` | 25.889 | 222.496 | **248.385** | 79.159 | 124.106 | 116.316 |
| `blake2b` | 29.580 | 298.826 | **328.406** | 82.192 | 126.128 | 110.315 |
| `sha512` | 29.308 | 365.818 | **395.126** | 82.934 | 120.703 | 100.910 |
| `x25519` | 28.670 | 632.278 | **660.948** | 80.979 | 943.872 | 408.753 |

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
