# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-27T05:42:06Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `dfe4bcb6c9422afb8922f6775df140d9571a2cad` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40456320221 |
| NURL | `v0.78.0-39-gdfe4bcb6` |
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
| _(floor: empty program)_ | _1.250_ | _1.187_ | _1.371_ | _19.090_ | _13.658_ |
| `lcg` | **34.135** | 34.175 | 34.309 | 1408.172 | 4193.401 |
| `packet_classifier` | 49.281 | **49.233** | 49.353 | 122.273 | 3620.242 |
| `ring_write` | 37.043 | **36.886** | 37.066 | 56.900 | 5109.921 |
| `histogram_bins` | **34.541** | 34.562 | 34.692 | 58.306 | 4744.018 |
| `prefix_scan` | 18.928 | **18.892** | 19.111 | 55.498 | 3578.160 |
| `binary_search` | 28.015 | **27.646** | 33.503 | 87.093 | 5314.615 |
| `sort_window` | 23.275 | **23.228** | 23.407 | 129.562 | 9306.272 |
| `bloom_filter` | **13.401** | 14.454 | 15.981 | 2111.969 | 6047.407 |
| `hash_join` | **21.369** | 22.213 | 23.360 | 2638.969 | 6299.216 |
| `sieve` | 15.887 | **15.603** | **15.603** | 55.888 | 2623.223 |
| `fib` | **25.700** | 25.710 | 25.790 | 110.086 | 1001.634 |
| `collatz` | 10.631 | **10.593** | 10.797 | 40.629 | 582.271 |
| `matmul` | 35.987 | 36.214 | **35.907** | 64.524 | 2727.543 |
| `json_parse` | **6.146** | 6.825 | 9.352 | 29.212 | 30.251 |
| `nbody` | **20.763** | 34.843 | 20.779 | 75.325 | 2567.663 |
| `chacha20` | **6.684** | 35.642 | 27.545 | n/a | n/a |
| `poly1305` | **9.832** | 31.190 | 18.478 | n/a | n/a |
| `blake2b` | **37.609** | 55.643 | 60.622 | n/a | n/a |
| `sha512` | **38.532** | 40.142 | 42.332 | n/a | n/a |
| `x25519` | **38.093** | 41.888 | 43.213 | n/a | n/a |

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
| _(floor: empty program)_ | _3.925_ | _98.351_ | _**102.276**_ | _54.264_ | _68.802_ | _44.956_ |
| `lcg` | 3.887 | 104.066 | **107.953** | 54.030 | 77.172 | 49.556 |
| `packet_classifier` | 4.072 | 105.138 | **109.210** | 53.992 | 78.459 | 49.931 |
| `ring_write` | 12.606 | 107.167 | **119.773** | 62.830 | 78.908 | 50.825 |
| `histogram_bins` | 12.704 | 108.344 | **121.048** | 63.833 | 91.227 | 56.605 |
| `prefix_scan` | 12.646 | 110.904 | **123.550** | 63.415 | 82.483 | 53.839 |
| `binary_search` | 12.713 | 108.369 | **121.082** | 63.659 | 79.678 | 54.412 |
| `sort_window` | 12.721 | 110.146 | **122.867** | 63.638 | 86.856 | 58.010 |
| `bloom_filter` | 13.148 | 111.307 | **124.455** | 64.213 | 85.581 | 55.193 |
| `hash_join` | 15.779 | 206.772 | **222.551** | 66.435 | 169.806 | 89.918 |
| `sieve` | 12.703 | 107.796 | **120.499** | 63.839 | 86.438 | 59.071 |
| `fib` | 4.041 | 104.976 | **109.017** | 53.924 | 77.759 | 49.601 |
| `collatz` | 4.157 | 107.486 | **111.643** | 54.126 | 78.254 | 49.821 |
| `matmul` | 13.832 | 108.920 | **122.752** | 64.809 | 88.421 | 65.787 |
| `json_parse` | 38.953 | 369.319 | **408.272** | 89.737 | 128.382 | 126.001 |
| `nbody` | 14.510 | 114.234 | **128.744** | 65.409 | 103.708 | 77.588 |
| `chacha20` | 43.910 | 619.462 | **663.372** | 94.137 | 114.131 | 87.849 |
| `poly1305` | 33.280 | 392.584 | **425.864** | 83.748 | 116.186 | 97.040 |
| `blake2b` | 30.632 | 295.277 | **325.909** | 81.263 | 119.299 | 93.798 |
| `sha512` | 30.689 | 359.836 | **390.525** | 81.039 | 113.268 | 82.966 |
| `x25519` | 30.437 | 624.187 | **654.624** | 80.357 | 930.054 | 386.367 |

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
